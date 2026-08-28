module InitSystems

  struct InitSystemInfo
    property kind
    property namespace
    property name
    property container
    property init_cmd
  
    def initialize(
      @kind : String,
      @namespace : String,
      @name : String,
      @container : String,
      @init_cmd : String
    )
    end
  end
  
  # By the executable's basename: a path that merely contains "tini" is not tini.
  def self.is_specialized_init_system?(cmd : String) : Bool
    SPECIALIZED_INIT_SYSTEMS.includes?(File.basename(cmd))
  end

  def self.scan(pod : JSON::Any) : Array(InitSystemInfo) | Nil
    failed_resources = [] of InitSystemInfo
    error_occurred = false

    nodes = KubectlClient::Get.nodes_by_pod(pod)
    pod_name = pod.dig("metadata", "name")
    resource_namespace = "default"
    if pod.dig?("metadata", "namespace")
      resource_namespace = pod.dig("metadata", "namespace").as_s
    end

    if nodes.size == 0
      Log.for("InitSystems.scan").info { "No nodes found for pod '#{pod_name}' in #{resource_namespace} namespace" }
      return failed_resources
    end

    pod_node = nodes[0]
    containers = pod.dig("status", "containerStatuses")
    containers.as_a.each do |container|
      container_id = container["containerID"]
      init_cmd = get_container_init_cmd(pod_node, container_id)
      if init_cmd != nil
        container_name = container["name"]
        container_init_cmd = init_cmd.not_nil!
        init_info = InitSystems::InitSystemInfo.new(
          "Pod",
          resource_namespace,
          pod_name.as_s,
          container_name.as_s,
          container_init_cmd
        )
        Log.for("InitSystems.scan").info { "#{init_info.kind}/#{init_info.name} has container '#{init_info.container}' with #{init_info.init_cmd} as init process" }
  
        if !InitSystems.is_specialized_init_system?(container_init_cmd)
          failed_resources << init_info
        end
      else
        error_occurred = true
      end
    end

    return error_occurred ? nil : failed_resources
  end

  def self.get_container_init_cmd(node, container_id) : String?
    container_id = ClusterTools.parse_container_id(container_id.as_s)
    pid = ClusterTools.node_pid_by_container_id(container_id, node)

    return nil if pid == nil
    
    result = KernelIntrospection::K8s::Node.cmdline_by_pid(pid.not_nil!, node)
    # Match the binary name before after splitting cmdline with \u0000
    cmdline = result[:output]
    cmdline_parts = cmdline.split("\u0000")
    return cmdline_parts[0]
  end
end
