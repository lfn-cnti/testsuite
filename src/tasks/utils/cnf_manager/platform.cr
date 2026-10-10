require "json"
require "yaml"

module CNFManager
  # The cluster the tests ran on, recorded in the results file when it is
  # created at the start of a run: the API server version, the provider, the
  # CNI where it can be told, and every node. A score is only interpretable
  # against the environment it was produced in (#2746). Collection tolerates
  # every failure: a run never fails because the platform could not be read.
  module Platform
    Log = ::Log.for("CNFManager::Platform")

    # Bounds each kubectl call, so a results file is created promptly with
    # `platform: null` when there is no reachable cluster.
    REQUEST_TIMEOUT = "5s"

    # DaemonSet name fragments that name a CNI.
    CNIS = ["kindnet", "calico", "cilium", "flannel", "weave", "antrea", "ovn"]

    def self.collect : YAML::Any
      nodes = run_json("kubectl get nodes --output json --request-timeout=#{REQUEST_TIMEOUT}")
      return YAML::Any.new(nil) if nodes.nil?
      version = run_json("kubectl version --output json --request-timeout=#{REQUEST_TIMEOUT}")
      daemonsets = run_json("kubectl get daemonsets --namespace kube-system --output json --request-timeout=#{REQUEST_TIMEOUT}")
      YAML.parse(from_json(version, nodes, daemonsets).to_json)
    rescue ex
      Log.warn { "Platform not recorded: #{ex.message}" }
      YAML::Any.new(nil)
    end

    # The platform record from the JSON of `kubectl version`, `kubectl get
    # nodes` and `kubectl get daemonsets -n kube-system`; the first and the
    # last may be missing.
    def self.from_json(version : JSON::Any?, nodes : JSON::Any, daemonsets : JSON::Any? = nil)
      items = nodes["items"]?.try(&.as_a?) || [] of JSON::Any
      {
        "kubernetes" => version.try(&.dig?("serverVersion", "gitVersion")).try(&.as_s?),
        "provider"   => provider_of(items),
        "cni"        => cni_of(daemonsets),
        "nodes"      => items.map { |node| node_record(node) },
      }
    end

    # The scheme of the nodes' providerID (`kind://docker/kind/kind-worker`,
    # `aws:///eu-west-1a/i-0123`), `none` when the nodes carry none.
    private def self.provider_of(nodes : Array(JSON::Any)) : String
      ids = nodes.compact_map { |n| n.dig?("spec", "providerID").try(&.as_s?) }.reject(&.empty?)
      return "none" if ids.empty?
      ids.first.partition("://")[0].partition(":")[0]
    end

    private def self.cni_of(daemonsets : JSON::Any?) : String?
      names = daemonsets.try(&.["items"]?).try(&.as_a?).try(&.compact_map { |d| d.dig?("metadata", "name").try(&.as_s?) }) || [] of String
      CNIS.find { |cni| names.any?(&.includes?(cni)) }
    end

    private def self.node_record(node : JSON::Any)
      info = node.dig?("status", "nodeInfo")
      capacity = node.dig?("status", "capacity")
      labels = node.dig?("metadata", "labels").try(&.as_h?) || {} of String => JSON::Any
      roles = labels.keys.select(&.starts_with?("node-role.kubernetes.io/")).map { |k| k.split("/", 2)[1] }.sort
      field = ->(source : JSON::Any?, key : String) { source.try(&.[key]?).try(&.as_s?) || "" }
      {
        "name"              => node.dig?("metadata", "name").try(&.as_s?) || "",
        "roles"             => roles,
        "kubelet"           => field.call(info, "kubeletVersion"),
        "os_image"          => field.call(info, "osImage"),
        "kernel"            => field.call(info, "kernelVersion"),
        "container_runtime" => field.call(info, "containerRuntimeVersion"),
        "architecture"      => field.call(info, "architecture"),
        "cpu"               => field.call(capacity, "cpu"),
        "memory"            => field.call(capacity, "memory"),
      }
    end

    private def self.run_json(cmd : String) : JSON::Any?
      result = KubectlClient::ShellCMD.run(cmd, Log.for("cmd"))
      return nil unless result[:status].success? && !result[:output].strip.empty?
      JSON.parse(result[:output])
    rescue ex
      Log.debug { "#{cmd}: #{ex.message}" }
      nil
    end
  end
end
