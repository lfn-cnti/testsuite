require "json"

# What elastic_volumes judges (#2665): the volume a claim is bound to, not
# the name of the provisioner that made it. A volume is elastic when it is not
# tied to one node, so the workload can be rescheduled with its data.
module VolumeElasticity
  HOSTNAME_KEYS         = ["kubernetes.io/hostname", "metadata.name"]
  DEFAULT_CLASS_ANNOTATIONS = ["storageclass.kubernetes.io/is-default-class", "storageclass.beta.kubernetes.io/is-default-class"]
  PROVISIONED_BY        = "pv.kubernetes.io/provisioned-by"

  # Why a PersistentVolume is tied to one node; nil when it is not. A node
  # affinity on a zone or a region, as cloud disks carry, does not tie it.
  def self.node_bound_reason(pv : JSON::Any) : String?
    if path = pv.dig?("spec", "local", "path").try(&.as_s?)
      return "a local volume at #{path}"
    end
    if path = pv.dig?("spec", "hostPath", "path").try(&.as_s?)
      return "a hostPath volume at #{path}"
    end
    terms = pv.dig?("spec", "nodeAffinity", "required", "nodeSelectorTerms").try(&.as_a?) || [] of JSON::Any
    terms.each do |term|
      ["matchExpressions", "matchFields"].each do |field|
        (term.dig?(field).try(&.as_a?) || [] of JSON::Any).each do |expression|
          next unless HOSTNAME_KEYS.includes?(expression.dig?("key").try(&.as_s?))
          nodes = (expression.dig?("values").try(&.as_a?) || [] of JSON::Any).compact_map(&.as_s?)
          return "pinned to node #{nodes.join(", ")}"
        end
      end
    end
    nil
  end

  # The provisioner that made the volume; nil for one created by hand.
  def self.provisioner(pv : JSON::Any) : String?
    pv.dig?("metadata", "annotations", PROVISIONED_BY).try(&.as_s?)
  end

  def self.default_class?(storage_class : JSON::Any?) : Bool
    return false unless storage_class
    DEFAULT_CLASS_ANNOTATIONS.any? { |key| storage_class.dig?("metadata", "annotations", key).try(&.as_s?) == "true" }
  end

  # Claims of a workload: those its pod volumes name, and for a StatefulSet
  # those made from its volumeClaimTemplates, one per template and replica.
  def self.claim_names(resource : JSON::Any) : Array(String)
    pod_spec = resource.dig?("spec", "template", "spec") || resource.dig?("spec")
    volumes = pod_spec.try(&.dig?("volumes")).try(&.as_a?) || [] of JSON::Any
    claims = volumes.compact_map(&.dig?("persistentVolumeClaim", "claimName").try(&.as_s?))
    templates = resource.dig?("spec", "volumeClaimTemplates").try(&.as_a?) || [] of JSON::Any
    name = resource.dig?("metadata", "name").try(&.as_s?)
    replicas = resource.dig?("spec", "replicas").try(&.as_i?) || 1
    if name
      templates.compact_map(&.dig?("metadata", "name").try(&.as_s?)).each do |template|
        replicas.times { |ordinal| claims << "#{template}-#{name}-#{ordinal}" }
      end
    end
    claims.uniq
  end

  enum Verdict
    Elastic
    NodeBound
    ClusterChoice
  end

  # A node-bound volume is the CNF's finding unless the cluster's default
  # storage class provisioned it: the CNF then took what the cluster offers.
  def self.judge(pv : JSON::Any, storage_class : JSON::Any?) : {verdict: Verdict, reason: String}
    class_name = pv.dig?("spec", "storageClassName").try(&.as_s?)
    origin = if made_by = provisioner(pv)
               "provisioned by #{made_by}#{class_name ? " (storage class #{class_name})" : ""}"
             else
               "created by hand#{class_name ? " (storage class #{class_name})" : ""}"
             end
    bound = node_bound_reason(pv)
    return {verdict: Verdict::Elastic, reason: "not tied to a node, #{origin}"} unless bound
    if provisioner(pv) && default_class?(storage_class)
      {verdict: Verdict::ClusterChoice, reason: "#{bound}, #{origin}, the cluster's default"}
    else
      {verdict: Verdict::NodeBound, reason: "#{bound}, #{origin}"}
    end
  end
end
