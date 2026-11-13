module ExecProbes
  PROBE_KEYS         = {"livenessProbe", "readinessProbe", "startupProbe"}
  MAX_PROBES         = 10
  MIN_PERIOD_SECONDS = 10

  def self.finding(probe : JSON::Any, exclusive_cpu_eligible : Bool) : String?
    reasons = [] of String
    reasons << "container is eligible for exclusive CPUs" if exclusive_cpu_eligible
    period = probe["periodSeconds"]?.try(&.as_i?) || MIN_PERIOD_SECONDS
    if period < MIN_PERIOD_SECONDS
      reasons << "periodSeconds is #{period}, below the minimum of #{MIN_PERIOD_SECONDS}"
    end
    reasons.empty? ? nil : reasons.join(" and ")
  end
end
