module CNFManager
  # Compare Kubernetes resource quantities by canonical value rather than by
  # string, so equal amounts written differently are treated as equal:
  # cpu "1" == "1000m", memory/hugepages "1Gi" == "1024Mi". Kubernetes itself
  # canonicalizes quantities, so a string comparison would raise false failures.
  module Quantity
    # Binary suffixes (checked first — they end in "i") and decimal/milli.
    BINARY = {
      "Ki" => 1024.0, "Mi" => 1048576.0, "Gi" => 1073741824.0,
      "Ti" => 1099511627776.0, "Pi" => 1125899906842624.0, "Ei" => 1152921504606846976.0,
    }
    DECIMAL = {
      "m" => 1e-3,
      "k" => 1e3, "M" => 1e6, "G" => 1e9, "T" => 1e12, "P" => 1e15, "E" => 1e18,
    }

    # The quantity as a Float64 in base units (cores for cpu, bytes for memory),
    # or nil when it cannot be parsed.
    def self.parse(quantity : String) : Float64?
      q = quantity.strip
      return nil if q.empty?
      BINARY.each do |suffix, factor|
        return q[0...(q.size - suffix.size)].to_f64?.try(&.* factor) if q.ends_with?(suffix)
      end
      DECIMAL.each do |suffix, factor|
        return q[0...(q.size - suffix.size)].to_f64?.try(&.* factor) if q.ends_with?(suffix)
      end
      q.to_f64?
    end

    # True when both parse to the same canonical value. Falls back to string
    # equality when either side is unparseable (so nothing regresses).
    def self.equal?(a : String?, b : String?) : Bool
      return false if a.nil? || b.nil?
      pa = parse(a)
      pb = parse(b)
      if pa && pb
        (pa - pb).abs <= 1e-9 * {1.0, pa.abs, pb.abs}.max
      else
        a == b
      end
    end
  end
end
