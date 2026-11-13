require "./quantity"

module ExecProbes
  PROBE_KEYS         = {"livenessProbe", "readinessProbe", "startupProbe"}
  MAX_PROBES         = 10
  MIN_PERIOD_SECONDS = 10

  def self.guaranteed?(containers : Array(JSON::Any)) : Bool
    !containers.empty? && containers.all? do |container|
      {"cpu", "memory"}.all? do |resource|
        limit = container.dig?("resources", "limits", resource).try(&.to_s)
        request = container.dig?("resources", "requests", resource).try(&.to_s) || limit
        amount = limit.try { |value| CNFManager::Quantity.parse(value) }
        amount && amount > 0 && CNFManager::Quantity.equal?(request, limit)
      end
    end
  end

  def self.exclusive_cpu_eligible?(container : JSON::Any) : Bool
    # A limit supplies the request when the manifest omits it.
    cpu = container.dig?("resources", "limits", "cpu").try { |value| CNFManager::Quantity.parse(value.to_s) }
    !cpu.nil? && cpu > 0 && cpu == cpu.floor
  end

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
