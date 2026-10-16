require "json"

# Whether a CNF's replicated workloads stay up through a node drain: a
# PodDisruptionBudget that selects them and allows an eviction, and replicas
# spread over nodes. Pure functions over the resources as JSON, so they can be
# unit-tested; the task in reliability.cr only gathers the resources.
module DisruptionBudget
  HOSTNAME_KEY = "kubernetes.io/hostname"

  record Workload, kind : String, name : String, namespace : String, replicas : Int32,
    labels : Hash(String, String), pod_spec : JSON::Any

  record Budget, name : String, namespace : String, spec : JSON::Any

  # A label selector against a set of labels. A missing selector matches
  # nothing; an empty one ({}) matches everything, as in policy/v1.
  def self.selects?(selector : JSON::Any?, labels : Hash(String, String)) : Bool
    return false if selector.nil? || selector.raw.nil?
    match_labels = selector.dig?("matchLabels").try(&.as_h?) || {} of String => JSON::Any
    return false unless match_labels.all? { |k, v| labels[k]? == v.as_s? }
    expressions = selector.dig?("matchExpressions").try(&.as_a?) || [] of JSON::Any
    expressions.all? do |e|
      key = e.dig?("key").try(&.as_s?) || ""
      values = (e.dig?("values").try(&.as_a?) || [] of JSON::Any).compact_map(&.as_s?)
      case e.dig?("operator").try(&.as_s?)
      when "In"           then labels.has_key?(key) && values.includes?(labels[key])
      when "NotIn"        then !labels.has_key?(key) || !values.includes?(labels[key])
      when "Exists"       then labels.has_key?(key)
      when "DoesNotExist" then !labels.has_key?(key)
      else                     false
      end
    end
  end

  # An int-or-percent against `total`, rounded up as the eviction API does.
  def self.scaled(value : JSON::Any, total : Int32) : Int32
    if (i = value.as_i?)
      i
    elsif (s = value.as_s?) && s.ends_with?("%")
      ((s.rchop("%").to_f * total) / 100.0).ceil.to_i
    else
      s.to_s.to_i? || 0
    end
  end

  # The workloads of the CNF a budget selects: same namespace, and its
  # selector matches their pod template labels.
  def self.selected(budget : Budget, workloads : Array(Workload)) : Array(Workload)
    workloads.select { |w| w.namespace == budget.namespace && selects?(budget.spec.dig?("selector"), w.labels) }
  end

  # How many of the selected pods a drain may evict at once, with all of them
  # healthy: maxUnavailable, or the selected replicas minus minAvailable. A
  # budget that sets neither allows none: the disruption controller reports
  # disruptionsAllowed 0 for it (checked on Kubernetes 1.37).
  def self.allowed_evictions(budget : Budget, expected : Int32) : Int32
    if max = budget.spec.dig?("maxUnavailable")
      scaled(max, expected)
    elsif min = budget.spec.dig?("minAvailable")
      expected - scaled(min, expected)
    else
      0
    end
  end

  # Why a budget allows no eviction, for the finding.
  def self.blocking_reason(budget : Budget, expected : Int32) : String
    cause = if budget.spec.dig?("maxUnavailable")
              "maxUnavailable: #{budget.spec["maxUnavailable"]}"
            elsif budget.spec.dig?("minAvailable")
              "minAvailable: #{budget.spec["minAvailable"]}"
            else
              "neither minAvailable nor maxUnavailable"
            end
    "allows no eviction of its #{expected} selected pod(s) (#{cause}), so it blocks every drain of their nodes"
  end

  # Whether the workload's own pods are spread over nodes, and what else was
  # seen that does not guarantee it (named in the details, not counted).
  def self.spread(workload : Workload) : {Bool, Array(String)}
    seen = [] of String
    terms = workload.pod_spec.dig?("affinity", "podAntiAffinity", "requiredDuringSchedulingIgnoredDuringExecution").try(&.as_a?) || [] of JSON::Any
    required = terms.any? do |t|
      t.dig?("topologyKey").try(&.as_s?) == HOSTNAME_KEY && selects?(t.dig?("labelSelector"), workload.labels)
    end
    preferred = workload.pod_spec.dig?("affinity", "podAntiAffinity", "preferredDuringSchedulingIgnoredDuringExecution").try(&.as_a?) || [] of JSON::Any
    if preferred.any? { |p| p.dig?("podAffinityTerm", "topologyKey").try(&.as_s?) == HOSTNAME_KEY }
      seen << "a preferred podAntiAffinity on #{HOSTNAME_KEY} (does not guarantee the spread)"
    end
    constraints = workload.pod_spec.dig?("topologySpreadConstraints").try(&.as_a?) || [] of JSON::Any
    spread_constraint = constraints.any? do |c|
      on_host = c.dig?("topologyKey").try(&.as_s?) == HOSTNAME_KEY && selects?(c.dig?("labelSelector"), workload.labels)
      if on_host && c.dig?("whenUnsatisfiable").try(&.as_s?) == "ScheduleAnyway"
        seen << "a topologySpreadConstraints entry on #{HOSTNAME_KEY} with whenUnsatisfiable: ScheduleAnyway (does not guarantee the spread)"
      end
      on_host && c.dig?("whenUnsatisfiable").try(&.as_s?) == "DoNotSchedule"
    end
    {required || spread_constraint, seen}
  end

  record Finding, kind : String, name : String, namespace : String, reason : String

  record Evaluation, findings : Array(Finding), details : Array(String), applicable : Bool

  # The test's decision over the CNF's workloads and budgets.
  def self.evaluate(workloads : Array(Workload), budgets : Array(Budget)) : Evaluation
    findings = [] of Finding
    details = [] of String

    budgets.each do |b|
      sel = selected(b, workloads)
      if sel.empty?
        details << "PodDisruptionBudget/#{b.name} in #{b.namespace}: selects no pod of the CNF"
        next
      end
      expected = sel.sum(&.replicas)
      allowed = allowed_evictions(b, expected)
      if allowed < 1
        findings << Finding.new("PodDisruptionBudget", b.name, b.namespace, blocking_reason(b, expected))
      else
        details << "PodDisruptionBudget/#{b.name} in #{b.namespace}: allows #{allowed} of #{expected} selected pod(s) to be evicted at once"
      end
    end

    multi = workloads.select { |w| w.replicas > 1 }
    multi.each do |w|
      missing = [] of String
      covering = budgets.select { |b| b.namespace == w.namespace && selects?(b.spec.dig?("selector"), w.labels) }
      missing << "no PodDisruptionBudget selects its pods" if covering.empty?
      spread_ok, seen = spread(w)
      missing << "its pods are not required to spread over nodes (no podAntiAffinity or DoNotSchedule topologySpreadConstraints on #{HOSTNAME_KEY} selecting them)" unless spread_ok
      seen.each { |s| details << "#{w.kind}/#{w.name} in #{w.namespace}: #{s}" }
      if missing.empty?
        # A budget that blocks every drain is reported as its own finding; the
        # workload is not "covered" by it.
        letting = covering.select { |b| allowed_evictions(b, selected(b, workloads).sum(&.replicas)) >= 1 }
        if letting.empty?
          names = covering.map { |b| "PodDisruptionBudget/#{b.name}" }.join(", ")
          details << "#{w.kind}/#{w.name} in #{w.namespace}: #{w.replicas} replicas, spread over nodes, but #{names} allows no eviction (reported above)"
        else
          b = letting.first
          allowed = allowed_evictions(b, selected(b, workloads).sum(&.replicas))
          details << "#{w.kind}/#{w.name} in #{w.namespace}: #{w.replicas} replicas, spread over nodes, and PodDisruptionBudget/#{b.name} lets a drain evict #{allowed} at a time"
        end
      else
        findings << Finding.new(w.kind, w.name, w.namespace, "#{w.replicas} replicas, but #{missing.join(", and ")}")
      end
    end

    Evaluation.new(findings, details, !(multi.empty? && budgets.empty?))
  end

  # The replicas a workload keeps running: an HPA's minReplicas when one in
  # its namespace targets it, else spec.replicas (1 when unset). `hpas` are
  # pairs of an HPA and its namespace.
  def self.replicas(resource : JSON::Any, namespace : String, hpas : Array({JSON::Any, String})) : Int32
    kind = resource.dig?("kind").try(&.as_s?)
    name = resource.dig?("metadata", "name").try(&.as_s?)
    hpa = hpas.find do |h, ns|
      ns == namespace && h.dig?("spec", "scaleTargetRef", "kind").try(&.as_s?) == kind &&
        h.dig?("spec", "scaleTargetRef", "name").try(&.as_s?) == name
    end.try(&.[0])
    if hpa
      hpa.dig?("spec", "minReplicas").try(&.as_i?) || 1
    else
      resource.dig?("spec", "replicas").try(&.as_i?) || 1
    end
  end
end
