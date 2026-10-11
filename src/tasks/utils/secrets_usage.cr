# How a CNF's workloads consume Kubernetes Secrets, for the secrets_used test:
# which Secrets a pod spec reads (a mounted secret volume, a projected
# source, an env secretKeyRef, an envFrom secretRef, an imagePullSecret), which
# Secrets the CNF ships in its namespaces, and what does not add up: a
# shipped Secret no workload reads, a required reference no Secret answers
# (#1936). Pure functions over the objects' JSON, so they are unit-tested.
module SecretsUsage
  # A reference a pod spec makes to a Secret: its name, where, and whether
  # the pod runs without it (`optional: true`).
  record Reference, name : String, where : String, optional : Bool

  # Every Secret a pod spec reads. A secret volume counts only when a
  # container mounts it: defined and unmounted, it reaches no process.
  def self.references(pod_spec : JSON::Any) : Array(Reference)
    refs = [] of Reference
    containers = ["initContainers", "containers", "ephemeralContainers"].flat_map { |k| pod_spec[k]?.try(&.as_a?) || [] of JSON::Any }
    mounted = containers.flat_map { |c| (c["volumeMounts"]?.try(&.as_a?) || [] of JSON::Any).compact_map { |m| m["name"]?.try(&.as_s?) } }.to_set

    (pod_spec["volumes"]?.try(&.as_a?) || [] of JSON::Any).each do |volume|
      vname = volume["name"]?.try(&.as_s?) || next
      next unless mounted.includes?(vname)
      if (secret = volume["secret"]?) && (name = secret["secretName"]?.try(&.as_s?))
        refs << Reference.new(name, "volume #{vname}", secret["optional"]?.try(&.as_bool?) || false)
      end
      (volume.dig?("projected", "sources").try(&.as_a?) || [] of JSON::Any).each do |source|
        if (secret = source["secret"]?) && (name = secret["name"]?.try(&.as_s?))
          refs << Reference.new(name, "projected volume #{vname}", secret["optional"]?.try(&.as_bool?) || false)
        end
      end
    end

    containers.each do |container|
      cname = container["name"]?.try(&.as_s?) || "?"
      (container["env"]?.try(&.as_a?) || [] of JSON::Any).each do |env|
        key_ref = env.dig?("valueFrom", "secretKeyRef") || next
        name = key_ref["name"]?.try(&.as_s?) || next
        refs << Reference.new(name, "env #{env["name"]?.try(&.as_s?)} of container #{cname}", key_ref["optional"]?.try(&.as_bool?) || false)
      end
      (container["envFrom"]?.try(&.as_a?) || [] of JSON::Any).each do |from|
        secret_ref = from["secretRef"]? || next
        name = secret_ref["name"]?.try(&.as_s?) || next
        refs << Reference.new(name, "envFrom of container #{cname}", secret_ref["optional"]?.try(&.as_bool?) || false)
      end
    end

    (pod_spec["imagePullSecrets"]?.try(&.as_a?) || [] of JSON::Any).each do |pull|
      name = pull["name"]?.try(&.as_s?) || next
      refs << Reference.new(name, "imagePullSecrets", true)
    end
    refs
  end

  # The names of the Secrets a namespace holds for the CNF: everything but the
  # kinds the cluster or the tooling keeps there (service account tokens,
  # registry credentials, Helm release records).
  def self.shipped(secrets : Array(JSON::Any)) : Array(String)
    secrets.compact_map do |s|
      next if IGNORED_SECRET_TYPES.includes?(s["type"]?.try(&.as_s?))
      s.dig?("metadata", "name").try(&.as_s?)
    end.sort
  end

  # What does not add up in a namespace: shipped Secrets no workload reads,
  # and required references no Secret of any type answers.
  def self.unused(shipped : Array(String), refs : Array(Reference)) : Array(String)
    read = refs.map(&.name).to_set
    shipped.reject { |name| read.includes?(name) }
  end

  def self.missing(all_secret_names : Array(String), refs : Array(Reference)) : Array(Reference)
    present = all_secret_names.to_set
    refs.reject { |ref| ref.optional || present.includes?(ref.name) }
  end
end
