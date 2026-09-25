module InitSystems

  struct InitSystemInfo
    property kind
    property namespace
    property name
    property container
    property init_cmd
    property specialized : Bool
    # False when PID 1's command line could not be read: such a container is
    # neither a pass nor a failure.
    property inspected : Bool

    def initialize(
      @kind : String,
      @namespace : String,
      @name : String,
      @container : String,
      @init_cmd : String,
      @specialized : Bool = false,
      @inspected : Bool = true
    )
    end
  end

  # Tries to read a container's PID 1: the first read, then a fresh look-up of
  # the container after each pause, since a container restarted by the test
  # before this one has a new ID and a new PID.
  INIT_CMD_ATTEMPTS = 3
  INIT_CMD_RETRY_DELAY = 2.seconds
  
  # By the executable's basename: a path that merely contains "tini" is not tini.
  def self.is_specialized_init_system?(cmd : String) : Bool
    SPECIALIZED_INIT_SYSTEMS.includes?(File.basename(cmd))
  end

  # Every container's PID 1 with whether it is a specialized init system;
  # nil when a container could not be inspected.
  def self.scan(pod : JSON::Any) : Array(InitSystemInfo) | Nil
    inspected = [] of InitSystemInfo
    error_occurred = false

    nodes = KubectlClient::Get.nodes_by_pod(pod)
    pod_name = pod.dig("metadata", "name")
    resource_namespace = "default"
    if pod.dig?("metadata", "namespace")
      resource_namespace = pod.dig("metadata", "namespace").as_s
    end

    if nodes.size == 0
      Log.for("InitSystems.scan").info { "No nodes found for pod '#{pod_name}' in #{resource_namespace} namespace" }
      return inspected
    end

    pod_node = nodes[0]
    containers = pod.dig("status", "containerStatuses")
    containers.as_a.each do |container|
      container_name = container["name"].as_s
      init_cmd = get_container_init_cmd(pod_node, container["containerID"])
      (INIT_CMD_ATTEMPTS - 1).times do
        break if init_cmd
        sleep INIT_CMD_RETRY_DELAY
        fresh_id = current_container_id(pod_name.as_s, resource_namespace, container_name)
        init_cmd = get_container_init_cmd(pod_node, fresh_id) if fresh_id
      end
      if init_cmd
        init_info = InitSystems::InitSystemInfo.new(
          "Pod",
          resource_namespace,
          pod_name.as_s,
          container_name,
          init_cmd,
          InitSystems.is_specialized_init_system?(init_cmd)
        )
        Log.for("InitSystems.scan").info { "#{init_info.kind}/#{init_info.name} has container '#{init_info.container}' with #{init_info.init_cmd} as init process" }
      else
        init_info = InitSystems::InitSystemInfo.new("Pod", resource_namespace, pod_name.as_s, container_name, "", inspected: false)
        Log.for("InitSystems.scan").warn { "Pod/#{pod_name} container '#{container_name}': PID 1's command line could not be read after #{INIT_CMD_ATTEMPTS} attempts" }
      end
      inspected << init_info
    end

    return error_occurred ? nil : inspected
  end

  # The container's ID as the cluster reports it now; nil if the pod or the
  # container is gone.
  def self.current_container_id(pod_name : String, namespace : String, container_name : String) : JSON::Any?
    pod = KubectlClient::Get.resource("pod", pod_name, namespace)
    status = pod.dig?("status", "containerStatuses").try(&.as_a?).try &.find { |cs| cs["name"]?.try(&.as_s?) == container_name }
    status.try(&.["containerID"]?)
  rescue
    nil
  end

  def self.get_container_init_cmd(node, container_id) : String?
    container_id = ClusterTools.parse_container_id(container_id.as_s)
    pid = ClusterTools.node_pid_by_container_id(container_id, node)

    return nil if pid == nil
    
    result = KernelIntrospection::K8s::Node.cmdline_by_pid(pid.not_nil!, node)
    init_cmd_from_cmdline(result[:output])
  end

  # The executable from a /proc/<pid>/cmdline read (NUL-separated); nil when
  # it is empty, as it is for a process that has exited or become a zombie
  # between the PID look-up and the read. That is not an init process.
  def self.init_cmd_from_cmdline(cmdline : String) : String?
    cmd = cmdline.split("\u0000").first?.to_s.strip
    cmd.empty? ? nil : cmd
  end
end
