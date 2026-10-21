require "../kubectl_client"
require "../docker_client"
require "../../tasks/setup/constants.cr"
require "file_utils"
require "log"
require "ecr"

module ClusterTools
  # Every log line of the module carries its scope (CNTI-ClusterTools).
  Log = ::Log.for("ClusterTools")

  # Default installation namespace
  @@namespace = "cnti-testsuite"

  class ManifestTemplate
    def initialize
    end

    ECR.def_to_s("#{__DIR__}/templates/manifest.yml.ecr")
  end

  def self.change_namespace(name)
    @@namespace = name
  end

  def self.namespace
    @@namespace
  end

  def self.namespace!
    self.ensure_namespace_exists!
    @@namespace
  end

  def self.ensure_namespace_exists!
    namespaces = KubectlClient::Get.resource("namespaces")
    namespace_array = namespaces["items"].as_a 

    Log.debug { "ensure_namespace_exists: namespaces #{namespace_array.map { |n| n.dig?("metadata", "name") }.compact.join(", ")}" }

    unless namespace_array.find{ |n| n.dig?("metadata", "name") == self.namespace }
      raise NamespaceDoesNotExistException.new("ClusterTools Namespace #{self.namespace} does not exist")
    end 

    true
  end

  def self.install()
    Log.info { "Installing cluster-tools" }
    FileUtils.mkdir_p(File.dirname(Setup::CLUSTER_TOOLS_MANIFEST))
    File.write(Setup::CLUSTER_TOOLS_MANIFEST, ManifestTemplate.new().to_s)
    KubectlClient::Apply.file(Setup::CLUSTER_TOOLS_MANIFEST, namespace: self.namespace!)
    wait_for_cluster_tools
  end

  def self.uninstall()
    Log.info { "Uninstalling cluster-tools" }
    FileUtils.mkdir_p(File.dirname(Setup::CLUSTER_TOOLS_MANIFEST))
    File.write(Setup::CLUSTER_TOOLS_MANIFEST, ManifestTemplate.new().to_s)

    KubectlClient::Delete.file(Setup::CLUSTER_TOOLS_MANIFEST, namespace: self.namespace!)
    #todo make this work with cluster-tools-host-namespace
    KubectlClient::Wait.resource_wait_for_uninstall("Daemonset", "cluster-tools", namespace: self.namespace!)
  ensure
    # Do not leave the rendered manifest behind after uninstalling
    FileUtils.rm_rf(Setup::CLUSTER_TOOLS_MANIFEST)
  end

  def self.exec(cli : String) : KubectlClient::CMDResult
    pods = KubectlClient::Get.pods_by_nodes(KubectlClient::Get.schedulable_nodes_list, namespace: self.namespace, label: {"name" => "cluster-tools"})
    cluster_tools_pod_name = pods[0].dig?("metadata", "name") if pods[0]?
    Log.debug { "cluster_tools_pod_name: #{cluster_tools_pod_name}"}

    KubectlClient::Utils.exec("#{cluster_tools_pod_name}", cli, namespace: self.namespace!)
  end

  def self.exec_by_node(cli : String, node_name : String) : KubectlClient::CMDResult?
    Log.debug { "exec_by_node: Called with String" }

    nodes = KubectlClient::Get.resource("nodes")["items"].as_a

    node : JSON::Any | Nil
    node = nodes.find{ |n| n.dig?("metadata", "name") == node_name }

    return self.exec_by_node(cli, node) if node

    Log.error { "exec_by_node failed, '#{node_name}' not matched to any existing nodes" }
    nil
  end
  
  private def self.get_cluster_tools_pod_on_node(node : JSON::Any)
    pods = KubectlClient::Get.pods_by_nodes([node], namespace: self.namespace, label: {"name" => "cluster-tools"})

    cluster_tools_pod_name = pods[0].dig?("metadata", "name") if pods[0]?
    Log.debug { "cluster_tools_pod_name: #{cluster_tools_pod_name}"}

    cluster_tools_pod_name
  end

  def self.exec_by_node(cli : String, node : JSON::Any) : KubectlClient::CMDResult
    Log.debug { "exec_by_node: Called with JSON" }
    pod_name = get_cluster_tools_pod_on_node(node)
    unless pod_name
      # Without the pod on the node the command cannot run at all: an empty pod
      # name makes kubectl fail with a message about a missing resource, which
      # reads like a failure of the command itself.
      node_name = node.dig?("metadata", "name")
      Log.error { "No cluster-tools pod on node #{node_name}" }
      return KubectlClient::CMDResult.new(status: Process::Status[1], output: "", error: "no cluster-tools pod on node #{node_name}")
    end
    exec = KubectlClient::Utils.exec("#{pod_name}", cli, namespace: self.namespace)
    Log.debug { "ClusterTools exec: #{exec}" }
    exec
  end

  def self.exec_by_node_bg(cli : String, node : JSON::Any) : KubectlClient::BackgroundCMDResult
    pod_name = get_cluster_tools_pod_on_node(node)
    exec = KubectlClient::Utils.exec_bg("#{pod_name}", cli, namespace: self.namespace)
    Log.debug { "ClusterTools exec: #{exec}" }
    exec
  end

  # todo make compatible with other runtimes
  def self.parse_container_id(container_id : String)
    Log.debug { "parse_container_id container_id: #{container_id}" }
    if container_id =~ /containerd/
      container_id.gsub("containerd://", "")[0..13] 
    else
      container_id
    end
  end

  def self.node_pid_by_container_id(container_id, node) : String | Nil
    inspect_container(container_id, node)[:pid]
  end

  # The node PID of a container from `crictl inspect`, with the reason it
  # could not be read. The two are told apart: a container the runtime does
  # not know is a CNF that has no container, while a lookup that did not work
  # (the cluster-tools pod is gone, the runtime socket is not linked, the
  # command did not reach the node) is a broken test harness, and the two are
  # not the same finding.
  def self.inspect_container(container_id, node) : NamedTuple(pid: String?, reason: String?)
    Log.debug {"node_pid_by_container_id container_id: #{container_id}" }
    short_container_id = parse_container_id(container_id)
    inspect = ClusterTools.exec_by_node("crictl inspect #{short_container_id}", node)
    unless inspect[:status].success?
      reason = inspect[:error].to_s.strip
      reason = "the runtime does not know the container" if reason.empty?
      # A reason the runtime did not give: whether the runtime of the node
      # answers at all tells a container that is gone from a runtime the
      # suite cannot reach.
      if !ClusterTools.harness_failure?(reason) && !ClusterTools.runtime_reachable?(node)
        reason = "the runtime of the node did not answer"
      end
      Log.error {"container_id not found for: #{container_id}: #{reason}" }
      return {pid: nil.as(String?), reason: reason}
    end

    Log.debug {"node_pid_by_container_id inspect: #{inspect[:output]}" }
    pid = running_pid_from_inspect(inspect[:output])
    Log.debug {"node_pid_by_container_id pid: #{pid}" }
    Log.warn {"container #{container_id} has no running process" } if pid.nil?
    {pid: pid, reason: pid.nil? ? "the container has no running process" : nil.as(String?)}
  end

  # Whether the runtime of the node answers through its cluster-tools pod.
  # The CNF's containers are read through it, so a node whose runtime does not
  # answer is a broken test harness and not a CNF that has no container.
  def self.runtime_reachable?(node) : Bool
    exec_by_node("crictl info", node)[:status].success?
  end

  # The messages of a command that did not reach the runtime of the node: the
  # cluster-tools pod is gone or not running, the runtime socket is not there,
  # the API server could not reach the pod.
  HARNESS_FAILURE_MARKERS = [
    "failed to connect",
    "connection refused",
    "no such file or directory",
    "error dialing backend",
    "unable to upgrade connection",
    "container not found (pod",
    "no cluster-tools pod on node",
    "context deadline exceeded",
    "timed out",
    "the server could not find the requested resource",
    "the runtime of the node did not answer",
  ]

  # Whether the reason a container could not be read is a failure of the test
  # harness rather than the CNF's container being absent. The runtime's own
  # message for a container it does not know is told apart from the messages
  # of a command that did not reach the runtime: the first is about the CNF,
  # the second is about the suite that cannot judge it.
  def self.harness_failure?(reason : String?) : Bool
    return false if reason.nil?
    text = reason.downcase
    # The runtime's answer for a container it does not know: the CNF's
    # container is gone, which is a finding about the CNF.
    return false if text.includes?("try to find container")
    HARNESS_FAILURE_MARKERS.any? { |marker| text.includes?(marker) }
  end

  # The node PID of a container from `crictl inspect`, or nil when the
  # container has no running process: crictl reports pid 0 for an exited
  # container, and the process tree of PID 0 would be every process on the
  # node (#2802).
  def self.running_pid_from_inspect(inspect_output : String) : String?
    pid = JSON.parse(inspect_output).dig?("info", "pid").try(&.raw).to_s
    pid.empty? || pid == "0" ? nil : pid
  rescue JSON::ParseException
    nil
  end
  # Zombies are invisible to cgroup-based enumeration on cgroup v1 nodes
  # (the kernel detaches exiting tasks from every v1 hierarchy), so they are
  # collected by state and matched to the container through their PPid: an
  # orphaned child is reparented to the container's init, so every zombie
  # belonging to the container has a parent among the container's pids.
  # On cgroup v2 nodes zombies are already in container_pids; the subtraction
  # keeps the result free of duplicates.
  def self.container_zombie_pids(container_pids : Array(String), node) : Array(String)
    zombie_pids = KernelIntrospection::K8s::Node.zombie_pids(node) - container_pids
    return zombie_pids if zombie_pids.empty?

    zombie_statuses = KernelIntrospection::K8s::Node.all_statuses_by_pids(zombie_pids, node)
    zombie_statuses.compact_map do |status|
      parsed = KernelIntrospection.parse_status(status)
      next unless parsed
      next unless container_pids.includes?(parsed["PPid"]?.try(&.strip))
      parsed["Pid"]?.try(&.strip)
    end
  end

  # What an enumeration could not read. A container that could not be
  # inspected is not yielded: the reason is kept here, so that a container the
  # harness could not read is told apart from a CNF that has no container to
  # read.
  class InspectionOutcome
    property reasons : Array(String) = [] of String
    # Whether the suite, and not the CNF, is what kept the container from
    # being read.
    property harness_broken : Bool = false

    def add(reason : String)
      @reasons << reason
      @harness_broken = true if ClusterTools.harness_failure?(reason)
    end

    def empty?
      @reasons.empty?
    end
  end

  #each_container_by_resource(resource, namespace) do | container_id, container_pid_on_node, node, container_proctree_statuses, container_status|
  # A container that could not be inspected is not yielded: the caller gets
  # the reason in `inspection`, so that a container the harness could not
  # read is told apart from a CNF that has no container to read.
  def self.all_containers_by_resource?(resource, namespace, only_container_pids : Bool = false, include_proctree : Bool = true, include_zombies : Bool = false, outcome : InspectionOutcome? = nil, &block) 
		kind = resource["kind"].downcase
		case kind
		when  "deployment","statefulset","pod","replicaset", "daemonset", "job", "cronjob"
			resource_yaml = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
			pods = KubectlClient::Get.pods_by_resource_labels(resource_yaml, resource[:namespace])
			pid_log_names  = [] of String
			pod_resp = pods.map do |pod|
				pod_name = pod.dig("metadata", "name")
				Log.debug { "pod_name: #{pod_name}" }

				status = pod["status"]
				if status["containerStatuses"]?
						container_statuses = status["containerStatuses"].as_a
					Log.debug { "container_statuses: #{container_statuses}" }
					Log.debug { "pod_name: #{pod_name}" }
					nodes = KubectlClient::Get.nodes_by_pod(pod)
					Log.debug { "nodes_by_resource done" }
					node = nodes.first # there should only be one node returned for one pod
					container_status_result = container_statuses.map do |container_status|
						container_name = container_status.dig("name")
						previous_process_type = "initial_name"
						# A container that has not started yet (its pod still Pending, an init
						# container running) has no ID: it is skipped like one that is not ready.
						prefix_container_id = container_status.dig?("containerID").try(&.as_s?)
						unless prefix_container_id
							Log.debug { "no containerID yet, skipping: #{container_name} in #{pod_name}" }
							next
						end
						container_id = prefix_container_id.gsub("containerd://", "")
						Log.debug { "before ready containerStatuses container_id #{container_id}" }
						ready = container_status.dig("ready").as_bool
						if !ready
							Log.debug { "container status: #{container_status} "}
							Log.debug { "not ready! skipping: containerStatuses container_id #{container_id}" }
							false
							next
						end
						# next unless ready 
						Log.debug { "containerStatuses container_id #{container_id}" }
						#get container id's pid on the node (different from inside the container)
						container_inspection = ClusterTools.inspect_container(container_id, node)
						container_pid_on_node = "#{container_inspection[:pid]}"
						if container_pid_on_node.empty?
							Log.debug { "no pid for (skipping): containerStatuses container_id #{container_id}" }
							outcome.add("#{pod_name} container #{container_name}: #{container_inspection[:reason]}") if outcome
							false
							next
						end

						# next if pid.empty?
						Log.debug { "node pid (should never be pid 1): #{container_pid_on_node}" }

						node_name = node.dig("metadata", "name").as_s
						Log.debug { "node name : #{node_name}" }
            if include_proctree
              if only_container_pids 
                pids = KernelIntrospection::K8s::Node.pids_by_container(container_id, node)
                if include_zombies
                  pids = pids + container_zombie_pids(pids + [container_pid_on_node], node)
                end
              else
                pids = KernelIntrospection::K8s::Node.pids(node)
              end

              if pids.empty?
                Log.debug { "pids empty #{pids}" }
                false
                next
              end

              Log.debug { "parsed pids: #{pids}" }
              proc_statuses = KernelIntrospection::K8s::Node.all_statuses_by_pids(pids, node)

              container_proctree_statuses = KernelIntrospection::K8s::Node.proctree_by_pid(container_pid_on_node, node, proc_statuses)
            else
              container_proctree_statuses = [] of Hash(String, String)
            end
						yield container_id, container_pid_on_node, node, container_proctree_statuses, container_status, pod_name
					end
          Log.debug { "container_status_result.all?(true): #{container_status_result.all?(true)}" }
          container_status_result.all?(true)
        else
          false
        end
			end
      Log.debug { "pod_resp.all?(true): #{pod_resp.all?(true)}" }                     
      pod_resp.all?(true)
    else
      true # non "deployment","statefulset","pod","replicaset", and "daemonset" dont have containers
		end
	end

  def self.wait_for_cluster_tools
    Log.info { "Waiting for cluster-tools to be ready" }
    installed = KubectlClient::Wait.resource_wait_for_install("Daemonset", "cluster-tools", namespace: self.namespace!, wait_count: 300)
    # The pods are waited for, but their readiness is not made a condition of
    # the installation: a node the CNF does not run on may have no usable pod
    # without that saying anything about the CNF. The nodes that are not ready
    # are named, and the tests that need them say so.
    wait_for_cluster_tools_pods_ready
    installed
  end

  # Every cluster-tools pod is running and ready. The pod is what the tests
  # read the CNF's containers through, and it is ready only when its runtime
  # socket is linked, so a pod that is still pulling its image, or that has no
  # runtime to read, is a node whose containers the suite cannot see. The
  # nodes that are not ready are named: a node without a usable pod is the
  # reason a test cannot judge the CNF, and it is worth saying which node.
  def self.wait_for_cluster_tools_pods_ready(timeout : Int32 = 300) : Bool
    Log.info { "Waiting for the cluster-tools pods to be ready on every node" }
    started = Time.utc
    loop do
      status = begin
        KubectlClient::Get.resource("daemonset", "cluster-tools", self.namespace)["status"]
      rescue
        nil
      end
      desired = status.try(&.dig?("desiredNumberScheduled")).try(&.as_i?) || 0
      ready = status.try(&.dig?("numberReady")).try(&.as_i?) || 0
      if desired > 0 && ready >= desired
        Log.info { "The cluster-tools pods are ready on the #{desired} node(s) that run them" }
        return true
      end
      if (Time.utc - started).total_seconds > timeout
        not_ready = cluster_tools_pods_not_ready
        Log.error { "The cluster-tools pods are not ready on every node: #{not_ready.join(", ")}. The CNF's containers cannot be read on those nodes." }
        return false
      end
      sleep 5.seconds
    end
  end

  # The cluster-tools pods that are not ready, by node. Every node counts,
  # tainted ones included: the pod runs on them too.
  def self.cluster_tools_pods_not_ready : Array(String)
    nodes = KubectlClient::Get.resource("nodes")["items"].as_a
    pods = KubectlClient::Get.pods_by_nodes(nodes, namespace: self.namespace, label: {"name" => "cluster-tools"})
    pods.reject { |pod| pod_ready?(pod) }.map do |pod|
      "#{pod.dig?("spec", "nodeName")} (#{pod.dig?("metadata", "name")}: #{pod.dig?("status", "phase")})"
    end
  rescue
    [] of String
  end

  # Whether the pod's containers are ready.
  def self.pod_ready?(pod : JSON::Any) : Bool
    statuses = pod.dig?("status", "containerStatuses").try(&.as_a?) || [] of JSON::Any
    !statuses.empty? && statuses.all? { |status| status["ready"]?.try(&.as_bool?) == true }
  end

  # https://windsock.io/explaining-docker-image-ids/
  # works on dockerhub and quay!
  # ex. kubectl exec cluster-tools-ww9lg -- skopeo inspect docker://jaegertracing/jaeger-agent:1.28.0
  # Accepts org/image:tag or repo/org/image:tag
  # A content digest is an uncompressed digest, which is what Kubernetes tracks 
  def self.official_content_digest_by_image_name(image_name)
    Log.debug { "official_content_digest_by_image_name: #{image_name}"}

    result = exec("skopeo inspect #{skopeo_creds} docker://#{image_name}")
    response = result[:output]
    if result[:status].success? && !response.empty?
      return JSON.parse(response)
    end
    JSON.parse(%({}))
  end

  # The registry credentials skopeo is given, from DOCKERHUB_USERNAME and
  # DOCKERHUB_PASSWORD; anonymous access when they are unset.
  def self.skopeo_creds : String
    if (u = ENV["DOCKERHUB_USERNAME"]?) && !u.empty? && (p = ENV["DOCKERHUB_PASSWORD"]?) && !p.empty?
      Log.debug { "Using USERNAME and PASSWORD for accessing the registry via skopeo" }
      "--creds #{u}:#{p}"
    else
      Log.debug { "Access the registry anonymously via skopeo" }
      ""
    end
  end

  # The tags of an image repository in its registry, listed by skopeo in
  # cluster-tools; nil when the registry cannot be read.
  def self.image_tags(repository : String) : Array(String)?
    result = exec("skopeo list-tags #{skopeo_creds} docker://#{repository}")
    return nil unless result[:status].success?
    JSON.parse(result[:output])["Tags"]?.try(&.as_a?).try(&.map(&.as_s))
  rescue JSON::ParseException
    nil
  end

  def self.local_match_by_image_name(image_names : Array(String), nodes=KubectlClient::Get.resource("nodes")["items"].as_a )
    image_names.map{|x| local_match_by_image_name(x, nodes)}.flatten.find{|m|m[:found]==true}
  end

  def self.local_match_by_image_name(image_name, nodes=KubectlClient::Get.resource("nodes")["items"].as_a )
    Log.debug { "local_match_by_image_name image_name: #{image_name}" }
    nodes = KubectlClient::Get.nodes["items"].as_a
    local_match_by_image_name(image_name, nodes)
  end

  # TODO (rafal-lal): add spec for it
  def self.local_match_by_image_name(image_name, nodes : Array(JSON::Any))
    Log.debug { "local_match_by_image_name image_name: #{image_name}" }

    match = Hash{:found => false, :digest => "", :release_name => ""}

    # Parse explicit tag and/or digest from image_name.
    # Supported formats:
    #   "org/image"
    #   "org/image:tag"
    #   "org/image:tag@sha256:digest"
    #   "org/image@sha256:digest"
    explicit_digest = ""
    explicit_tag = ""
    base_image_name = image_name

    if (at_idx = image_name.index("@"))
      base_part = image_name[0...at_idx]
      explicit_digest = image_name[at_idx + 1..]  # e.g. "sha256:abc123"
      last_slash = base_part.rindex("/") || -1
      last_seg = base_part[last_slash + 1..]
      if (colon_idx = last_seg.index(":"))
        explicit_tag = last_seg[colon_idx + 1..]
        base_image_name = base_part[0...last_slash + 1] + last_seg[0...colon_idx]
      else
        base_image_name = base_part
      end
    else
      last_slash = image_name.rindex("/") || -1
      last_seg = image_name[last_slash + 1..]
      if (colon_idx = last_seg.index(":"))
        explicit_tag = last_seg[colon_idx + 1..]
        base_image_name = image_name[0...last_slash + 1] + last_seg[0...colon_idx]
      end
    end

    Log.debug { "local_match_by_image_name base_image_name: #{base_image_name}, explicit_tag: #{explicit_tag}, explicit_digest: #{explicit_digest}" }

    # Group all imageIDs on passed 'nodes' into array.
    # If 'base_image_name' matches the name with tag, save its first occurence.
    # node.status.images is in following format:
    #  {
    #  "names": [
    #    "registry.k8s.io/kube-state-metrics/kube-state-metrics@sha256:37d84129932.......",
    #    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0"
    #  ],
    #  "sizeBytes": 51212837
    #  }
    tag = explicit_tag
    imageIDs = [] of String
    nodes.each do |node|
      begin
        node.dig("status", "images").as_a.each do |image|
          image.dig("names").as_a.each do |name|
            if name.as_s.includes?("sha256")
              imageIDs << name.as_s
            else
              next unless name.as_s.includes?(base_image_name)
              tag = DockerClient.parse_image(name.as_s)["tag"] if tag.empty?
            end
          end
        end
      rescue
        next
      end
    end
    Log.debug { "local_match_by_image_name imageIDs : #{imageIDs}" }

    if !explicit_digest.empty?
      # Use the digest provided in image_name directly; skip the skopeo registry call.
      Log.debug { "local_match_by_image_name using explicit digest: #{explicit_digest}" }
      sha_list = [{"name" => base_image_name, "manifest_digest" => explicit_digest}]
      match = DockerClient::K8s.local_digest_match(sha_list, imageIDs)
      Log.debug { "local_match_by_image_name match : #{match}"}
    elsif !tag.empty?
      Log.debug { "container tag: #{tag}" }
      resp = ClusterTools.official_content_digest_by_image_name(base_image_name + ":" + tag)
      sha_list = [{"name" => base_image_name, "manifest_digest" => resp["Digest"].as_s}]
      Log.debug { "jaeger_pods sha_list : #{sha_list}"}
      match = DockerClient::K8s.local_digest_match(sha_list, imageIDs)
      Log.debug { "local_match_by_image_name match : #{match}"}
    else
      Log.debug { "local_match_by_image_name tag: #{tag} match : #{match}"}
      match[:found]=false
    end
    Log.debug { "local_match_by_image_name match: #{match}" }
    match
  end

  def self.pod_name()
    KubectlClient::Get.match_pods_by_prefix("cluster-tools", namespace: self.namespace!).first?
  end

  def self.pod_by_node(node)
    resource = KubectlClient::Get.resource("Daemonset", "cluster-tools", namespace: self.namespace!)
    pods = KubectlClient::Get.pods_by_resource_labels(resource, namespace: self.namespace!)
    cluster_pod = pods.find do |pod|
      pod.dig("spec", "nodeName") == node
    end
    cluster_pod.dig("metadata", "name") if cluster_pod
  end


  def self.cluster_tools_pod_by_node(node_name)
    Log.debug { "cluster_tools_pod_by_node node_name: #{node_name}" }
    cluster_tools_pod = self.pod_by_node(node_name)
  end
  
  class NamespaceDoesNotExistException < Exception
  end
end
