require "yaml"
require "../constants"

# Static lint for hugepages emptyDir volumes, kept pure (manifest in, findings
# out) so it can be unit-tested without a cluster.
#
# The kubelet requires an emptyDir volume with a HugePages medium to be backed by
# a hugepages resource request somewhere in the *pod*: a `HugePages-<size>` medium
# needs a container or init container that asks for `hugepages-<size>`, and a
# generic `HugePages` medium needs the pod to ask for hugepages in exactly one
# page size. The API server accepts a manifest that breaks this; it fails only on
# the node (the pod stays in ContainerCreating with a FailedMount event), which
# is hard to diagnose — so this catches it from the manifest instead.
module HugepagesVolumes
  record Violation,
    kind : String,
    name : String,
    namespace : String?,
    volume : String,
    reason : String

  # Returns the pod spec (the level that holds containers/volumes) for a workload
  # manifest, or nil if the resource is not a workload we inspect.
  def self.pod_spec(resource : YAML::Any) : YAML::Any?
    kind = resource["kind"]?.try(&.as_s?).try(&.downcase)
    return nil unless kind && WORKLOAD_RESOURCE_KIND_NAMES.includes?(kind)
    kind == "pod" ? resource.dig?("spec") : resource.dig?("spec", "template", "spec")
  end

  # The hugepage page sizes the pod requests, gathered across every container and
  # init container and from both requests and limits (a hugepages limit with no
  # request is valid — Kubernetes defaults the request from it).
  def self.requested_page_sizes(pod_spec : YAML::Any) : Array(String)
    sizes = [] of String
    {"containers", "initContainers"}.each do |field|
      (pod_spec.dig?(field).try(&.as_a?) || [] of YAML::Any).each do |container|
        {"requests", "limits"}.each do |kind|
          (container.dig?("resources", kind).try(&.as_h?) || {} of YAML::Any => YAML::Any).each_key do |key|
            k = key.as_s
            sizes << k.sub("hugepages-", "") if k.starts_with?("hugepages-")
          end
        end
      end
    end
    sizes.uniq
  end

  # Lints every workload in the manifests. Returns the violations and how many
  # pods declare a hugepages volume (so callers report `na` when none do — a
  # container that asks for hugepages without such a volume is legitimate and
  # leaves nothing to check).
  def self.check(resources : Array(YAML::Any)) : NamedTuple(violations: Array(Violation), pods_with_hugepages_volume: Int32)
    violations = [] of Violation
    pods_with_hugepages_volume = 0

    resources.each do |resource|
      spec = pod_spec(resource)
      next unless spec

      kind = resource["kind"].as_s
      name = resource.dig?("metadata", "name").try(&.as_s?) || ""
      namespace = resource.dig?("metadata", "namespace").try(&.as_s?)

      hugepage_volumes = (spec.dig?("volumes").try(&.as_a?) || [] of YAML::Any).select do |volume|
        (volume.dig?("emptyDir", "medium").try(&.as_s?) || "").starts_with?("HugePages")
      end
      next if hugepage_volumes.empty?
      pods_with_hugepages_volume += 1

      sizes = requested_page_sizes(spec)

      hugepage_volumes.each do |volume|
        vol_name = volume.dig?("name").try(&.as_s?) || ""
        medium = volume.dig?("emptyDir", "medium").try(&.as_s?) || ""

        if medium == "HugePages"
          # A size-less medium needs the pod to request hugepages in one size only.
          if sizes.empty?
            violations << Violation.new(kind, name, namespace, vol_name,
              "emptyDir hugepages volume '#{vol_name}' (medium HugePages) is not backed by any hugepages request in the pod")
          elsif sizes.size > 1
            violations << Violation.new(kind, name, namespace, vol_name,
              "emptyDir hugepages volume '#{vol_name}' uses the size-less medium HugePages but the pod requests more than one page size (#{sizes.sort.join(", ")}); use a size-specific medium")
          end
        else
          size = medium.sub("HugePages-", "")
          unless sizes.includes?(size)
            violations << Violation.new(kind, name, namespace, vol_name,
              "emptyDir hugepages volume '#{vol_name}' medium '#{medium}' is not backed by a container requesting hugepages-#{size}")
          end
        end
      end
    end

    {violations: violations, pods_with_hugepages_volume: pods_with_hugepages_volume}
  end
end
