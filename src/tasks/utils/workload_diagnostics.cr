# Why a workload is not where a test expected it: the state of its pods and
# the cluster's own explanation in Warning events. Read when a test fails
# because pods did not come up or come back, so the result carries the cause
# (FailedScheduling, ImagePullBackOff, an exceeded quota, ...) instead of
# leaving the user to reconstruct it from a cluster that has moved on.
module WorkloadDiagnostics
  EVENT_LIMIT = 8

  # One line per pod that is not Ready, then the recent Warning events about
  # the workload, its ReplicaSets and its pods.
  def self.problems(kind : String, name : String, namespace : String) : Array(String)
    lines = [] of String
    begin
      resource = KubectlClient::Get.resource(kind, name, namespace)
      pods = KubectlClient::Get.pods_by_resource_labels(resource, namespace)
      pods.each do |pod|
        pod_name = pod.dig("metadata", "name").as_s
        phase = pod.dig?("status", "phase").try(&.as_s) || "Unknown"
        conditions = (pod.dig?("status", "conditions").try(&.as_a?) || [] of JSON::Any)
        ready = conditions.any? { |c| c.dig?("type").try(&.as_s) == "Ready" && c.dig?("status").try(&.as_s) == "True" }
        next if ready
        why = [] of String
        conditions.each do |c|
          next if c.dig?("status").try(&.as_s) == "True"
          detail = [c.dig?("reason").try(&.as_s), c.dig?("message").try(&.as_s)].compact.join(": ")
          why << "#{c.dig?("type").try(&.as_s)}=False#{detail.empty? ? "" : " (#{detail})"}"
        end
        (pod.dig?("status", "containerStatuses").try(&.as_a?) || [] of JSON::Any).each do |cs|
          if waiting = cs.dig?("state", "waiting")
            detail = [waiting.dig?("reason").try(&.as_s), waiting.dig?("message").try(&.as_s)].compact.join(": ")
            why << "container #{cs.dig?("name").try(&.as_s)} waiting#{detail.empty? ? "" : " (#{detail})"}"
          end
        end
        lines << "pod #{pod_name}: #{phase}#{why.empty? ? "" : "; " + why.join("; ")}"
      end
      lines.concat(warning_events(kind, name, namespace, pods.map { |p| p.dig("metadata", "name").as_s }))
    rescue ex
      Log.for("WorkloadDiagnostics").warn { "could not collect diagnostics for #{kind}/#{name} in #{namespace}: #{ex.message}" }
    end
    lines
  end

  # Recent Warning events whose object is the workload, one of its pods, or a
  # ReplicaSet named after it (a Deployment's pods are created through those,
  # and a creation the cluster refuses is reported there, not on any pod).
  def self.warning_events(kind : String, name : String, namespace : String, pod_names : Array(String)) : Array(String)
    events = KubectlClient::Get.resource("events", namespace: namespace).dig?("items").try(&.as_a?) || [] of JSON::Any
    relevant = events.select do |e|
      next false unless e.dig?("type").try(&.as_s) == "Warning"
      obj_kind = e.dig?("involvedObject", "kind").try(&.as_s) || ""
      obj_name = e.dig?("involvedObject", "name").try(&.as_s) || ""
      (obj_kind == kind && obj_name == name) ||
        (obj_kind == "Pod" && pod_names.includes?(obj_name)) ||
        (obj_kind == "ReplicaSet" && obj_name.starts_with?("#{name}-"))
    end
    relevant = relevant.sort_by { |e| (e.dig?("lastTimestamp") || e.dig?("eventTime") || e.dig?("metadata", "creationTimestamp")).try(&.as_s?) || "" }
    seen = Set(String).new
    relevant.reverse.compact_map do |e|
      reason = e.dig?("reason").try(&.as_s) || ""
      message = (e.dig?("message").try(&.as_s) || "").lines.first?.to_s.strip
      key = "#{reason}|#{message}"
      next if seen.includes?(key)
      seen << key
      "event #{e.dig?("involvedObject", "kind").try(&.as_s)}/#{e.dig?("involvedObject", "name").try(&.as_s)}: #{reason}: #{message}"
    end.first(EVENT_LIMIT)
  end

  # Appends the collected lines to the result's details, under a heading.
  def self.report(result, kind : String, name : String, namespace : String, heading : String) : Array(String)
    lines = problems(kind, name, namespace)
    unless lines.empty?
      result.append_description("#{heading}:")
      lines.each { |line| result.append_description("  #{line}") }
    end
    lines
  end
end
