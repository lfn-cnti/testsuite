# Why a workload is not where a test expected it: the state of its pods and
# the cluster's own explanation in Warning events. Read when a test fails
# because pods did not come up or come back, so the result carries the cause
# (FailedScheduling, ImagePullBackOff, an exceeded quota, ...) instead of
# leaving the user to reconstruct it from a cluster that has moved on.
module WorkloadDiagnostics
  EVENT_LIMIT = 8
  # One restart can be a crash for any reason; a loop takes more.
  CRASH_LOOP_RESTARTS = 2

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
          crash_loop(cs).try { |line| why << line }
        end
        lines << "pod #{pod_name}: #{phase}#{why.empty? ? "" : "; " + why.join("; ")}"
      end
      lines.concat(warning_events(kind, name, namespace, pods.map { |p| p.dig("metadata", "name").as_s }))
    rescue ex
      Log.for("WorkloadDiagnostics").warn { "could not collect diagnostics for #{kind}/#{name} in #{namespace}: #{ex.message}" }
    end
    lines
  end

  # A container caught between the restarts of a crash loop: it shows
  # CrashLoopBackOff only while it waits for the next one, and a read at another
  # moment finds it running or just ended. Its restarts and last exit code say
  # the same at any moment. Nil for a container that is ready or that waits.
  def self.crash_loop(container_status : JSON::Any) : String?
    return nil if container_status["ready"]?.try(&.as_bool?) || container_status.dig?("state", "waiting")
    restarts = container_status["restartCount"]?.try(&.as_i?) || 0
    return nil if restarts < CRASH_LOOP_RESTARTS
    terminated = container_status.dig?("state", "terminated") || container_status.dig?("lastState", "terminated")
    exit_code = terminated.try(&.dig?("exitCode")).try(&.as_i?) || 0
    return nil if exit_code.zero?
    "container #{container_status.dig?("name").try(&.as_s)} crash-looping (restarted #{restarts} times, last exit code #{exit_code})"
  end

  # Whether a line of problems says this container is in a crash loop. A pod's
  # line holds the reasons of all its containers, so a sidecar's loop says
  # nothing about the container beside it.
  def self.crash_looping?(line : String, container : String) : Bool
    line.includes?("container #{container} waiting (CrashLoopBackOff") || line.includes?("container #{container} crash-looping")
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

  # The last lines each container of the workload's pods logged, and for a
  # container that has restarted, the last lines of its previous run: the
  # reason a crash-looping container died is in the run before the current one.
  # With `unready_only`, only the pods that are not Ready: the ones a test
  # asks about, not the ones that are fine.
  def self.log_tails(kind : String, name : String, namespace : String, tail : Int32 = 40, unready_only : Bool = false) : Array(String)
    sections = [] of String
    begin
      resource = KubectlClient::Get.resource(kind, name, namespace)
      KubectlClient::Get.pods_by_resource_labels(resource, namespace).each do |pod|
        next if unready_only && pod_ready?(pod)
        pod_name = pod.dig("metadata", "name").as_s
        (pod.dig?("status", "containerStatuses").try(&.as_a?) || [] of JSON::Any).each do |cs|
          container = cs.dig("name").as_s
          runs = [{"current", ""}]
          runs << {"previous", " --previous"} if (cs.dig?("restartCount").try(&.as_i?) || 0) > 0
          runs.each do |(which, flag)|
            begin
              output = KubectlClient::Utils.logs(pod_name, container, namespace, "--tail=#{tail}#{flag}")[:output].to_s.strip
              sections << "--- #{which} log of pod #{pod_name} container #{container} ---\n#{output.empty? ? "(empty)" : output}"
            rescue ex
              sections << "--- #{which} log of pod #{pod_name} container #{container}: not available (#{ex.message.to_s.lines.first?.to_s.strip}) ---"
            end
          end
        end
      end
    rescue ex
      Log.for("WorkloadDiagnostics").warn { "could not collect logs for #{kind}/#{name} in #{namespace}: #{ex.message}" }
    end
    sections
  end

  # Lines of log kept per container in the result's details; the suite log
  # carries a longer tail.
  DETAIL_LOG_LINES = 12
  LOG_LINES        = 40

  # Appends the collected lines to the result's details, under a heading:
  # the pods that are not Ready with the cluster's Warning events, then the
  # last lines those pods logged (and the previous run of a container that
  # restarted). Conditions and events say that a pod is not Ready; only its
  # own log says why. Returns the problem lines, without the logs.
  def self.report(result, kind : String, name : String, namespace : String, heading : String) : Array(String)
    lines = problems(kind, name, namespace)
    unless lines.empty?
      result.append_description("#{heading}:")
      lines.each { |line| result.append_description("  #{line}") }
      tails = log_tails(kind, name, namespace, tail: LOG_LINES, unready_only: true)
      tails.each { |section| Log.for("WorkloadDiagnostics").info { "#{heading}\n#{section}" } }
      tails.each do |section|
        header, _, body = section.partition("\n")
        result.append_description("  #{header}")
        body.lines.last(DETAIL_LOG_LINES).each { |line| result.append_description("    #{line.rstrip}") }
      end
    end
    lines
  end

  def self.pod_ready?(pod : JSON::Any) : Bool
    conditions = pod.dig?("status", "conditions").try(&.as_a?) || [] of JSON::Any
    conditions.any? { |c| c.dig?("type").try(&.as_s?) == "Ready" && c.dig?("status").try(&.as_s?) == "True" }
  end
end
