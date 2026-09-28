require "yaml"
require "./quantity"
require "../constants"

# Static lint for hugepages declarations, kept pure (manifest in, findings out)
# so it can be unit-tested without a cluster. It reads the CNF's *declared*
# manifest rather than a live resource: a workload that misdeclares hugepages is
# rejected by the Kubernetes API server at apply time, so the value of this check
# is catching the misdeclaration in the rendered manifest *before* it is applied
# (a clear message instead of an opaque admission or scheduling failure).
module HugepagesLint
  record Violation,
    kind : String,
    name : String,
    namespace : String?,
    container : String,
    reason : String

  # Returns the pod spec (the level that holds containers/volumes) for a workload
  # manifest, or nil if the resource is not a workload we inspect.
  def self.pod_spec(resource : YAML::Any) : YAML::Any?
    kind = resource["kind"]?.try(&.as_s?).try(&.downcase)
    return nil unless kind && WORKLOAD_RESOURCE_KIND_NAMES.includes?(kind)
    kind == "pod" ? resource.dig?("spec") : resource.dig?("spec", "template", "spec")
  end

  # Lints every workload container in the given manifests. Returns the list of
  # violations and how many containers actually requested hugepages (so callers
  # can report `na` when none do).
  def self.check(resources : Array(YAML::Any)) : NamedTuple(violations: Array(Violation), hugepage_containers: Int32)
    violations = [] of Violation
    hugepage_containers = 0

    resources.each do |resource|
      spec = pod_spec(resource)
      next unless spec

      kind = resource["kind"].as_s
      name = resource.dig?("metadata", "name").try(&.as_s?) || ""
      namespace = resource.dig?("metadata", "namespace").try(&.as_s?)
      volumes = spec.dig?("volumes").try(&.as_a?) || [] of YAML::Any

      (spec.dig?("containers").try(&.as_a?) || [] of YAML::Any).each do |container|
        container_name = container.dig?("name").try(&.as_s?) || ""

        res = container.dig?("resources")
        requests = res.try(&.dig?("requests"))
        limits = res.try(&.dig?("limits"))

        request_keys = (requests.try(&.as_h?).try(&.keys) || [] of YAML::Any).map(&.as_s)
        limit_keys = (limits.try(&.as_h?).try(&.keys) || [] of YAML::Any).map(&.as_s)
        request_hugepages = request_keys.select(&.starts_with?("hugepages-"))
        hugepage_keys = (request_hugepages + limit_keys.select(&.starts_with?("hugepages-"))).uniq

        # No hugepages on this container: the check does not apply to it.
        next if hugepage_keys.empty?
        hugepage_containers += 1

        # (a) requests == limits for every hugepages resource.
        hugepage_keys.each do |key|
          req = requests.try(&.[key]?)
          lim = limits.try(&.[key]?)
          if req.nil? || lim.nil? || !CNFManager::Quantity.equal?(req.to_s, lim.to_s)
            violations << Violation.new(kind, name, namespace, container_name,
              "#{key} request (#{req.try(&.to_s) || "unset"}) and limit (#{lim.try(&.to_s) || "unset"}) must be set and equal")
          end
        end

        # (b) a cpu or memory request must also be present.
        unless requests.try(&.["cpu"]?) || requests.try(&.["memory"]?)
          violations << Violation.new(kind, name, namespace, container_name,
            "missing cpu or memory request required for a hugepages consumer")
        end

        # (c) any emptyDir volume advertising a HugePages medium must name a page
        # size this container requested (a generic `HugePages` medium is allowed).
        requested_sizes = request_hugepages.map { |k| k.sub("hugepages-", "").downcase }
        volumes.each do |volume|
          medium = volume.dig?("emptyDir", "medium").try(&.as_s?)
          next unless medium && medium.starts_with?("HugePages")
          next if medium == "HugePages"
          size = medium.sub("HugePages-", "").downcase
          unless requested_sizes.includes?(size)
            violations << Violation.new(kind, name, namespace, container_name,
              "emptyDir hugepages medium '#{medium}' does not match a requested page size")
          end
        end
      end
    end

    {violations: violations, hugepage_containers: hugepage_containers}
  end
end
