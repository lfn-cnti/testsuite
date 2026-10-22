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

    # A ready pod first: while the DaemonSet rolls, a node briefly has a
    # terminating pod next to the new one.
    pod = pods.find { |p| helper_pod_ready?(p) } || pods[0]?
    cluster_tools_pod_name = pod.try &.dig?("metadata", "name")
    Log.debug { "cluster_tools_pod_name: #{cluster_tools_pod_name}"}

    cluster_tools_pod_name
  end

  def self.exec_by_node(cli : String, node : JSON::Any) : KubectlClient::CMDResult
    Log.debug { "exec_by_node: Called with JSON" }
    pod_name = get_cluster_tools_pod_on_node(node)
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

  # Container ID without its runtime prefix, e.g. "containerd://" or
  # "cri-o://". crictl takes the bare ID; leaving the prefix on makes the node
  # PID lookup fail on every runtime but containerd.
  def self.strip_runtime_prefix(container_id : String) : String
    container_id.split("://", 2).last
  end

  def self.parse_container_id(container_id : String)
    Log.debug { "parse_container_id container_id: #{container_id}" }
    bare_id = strip_runtime_prefix(container_id)
    if container_id =~ /containerd/
      bare_id[0..13]
    else
      bare_id
    end
  end

  def self.node_pid_by_container_id(container_id, node) : String | Nil
    pid_or_reason(container_id, node)[:pid]
  end

  # The container's PID on its node, or why it could not be read (#2824): the
  # one reason the tests put in their details, computed here where the
  # look-up fails. A container ID of another runtime is refused before the
  # node is asked anything; then the helper pod has to be on the node and
  # ready, crictl has to know the container, and the container has to run.
  def self.pid_or_reason(container_id : String, node : JSON::Any) : NamedTuple(pid: String?, reason: String?)
    Log.debug { "pid_or_reason container_id: #{container_id}" }
    if (runtime = container_id.partition("://")[0]) && container_id.includes?("://") && runtime != "containerd"
      return {pid: nil, reason: "container ID #{container_id} is a #{runtime} ID; the suite inspects containers through containerd only"}
    end
    node_name = node.dig?("metadata", "name").try(&.as_s?) || "?"
    unless helper_ready_on_node?(node)
      return {pid: nil, reason: "cluster-tools has no ready pod on node #{node_name}"}
    end
    short_container_id = parse_container_id(container_id)
    inspect = ClusterTools.exec_by_node("crictl inspect #{short_container_id}", node)
    unless inspect[:status].success?
      why = crictl_error(inspect[:error].to_s, inspect[:output].to_s)
      Log.error { "container_id not found for: #{container_id}: #{why}" }
      return {pid: nil, reason: "crictl inspect #{short_container_id} on node #{node_name} failed: #{why}"}
    end
    Log.debug { "pid_or_reason inspect: #{inspect[:output]}" }
    pid = running_pid_from_inspect(inspect[:output])
    Log.debug { "pid_or_reason pid: #{pid}" }
    return {pid: pid, reason: nil} if pid
    Log.warn { "container #{container_id} has no running process" }
    {pid: nil, reason: "crictl reports no running process for container #{short_container_id} on node #{node_name} (exited?)"}
  end

  # A cluster-tools pod on the node with its container ready.
  def self.helper_ready_on_node?(node : JSON::Any) : Bool
    pods = KubectlClient::Get.pods_by_nodes([node], namespace: self.namespace, label: {"name" => "cluster-tools"})
    pods.any? { |pod| helper_pod_ready?(pod) }
  rescue KubectlClient::ShellCMD::K8sClientCMDException
    false
  end

  private def self.helper_pod_ready?(pod : JSON::Any) : Bool
    (pod.dig?("status", "containerStatuses").try(&.as_a?) || [] of JSON::Any).any? { |c| c["ready"]?.try(&.as_bool?) == true }
  end

  # crictl's own error from a failed call. crictl logs through logrus, so the
  # error is a `time="…" level=fatal msg="…"` line, next to warnings such as
  # the one about default endpoints: the warnings are dropped and the error's
  # message is the reason. Anything else on stderr, then stdout, follows.
  def self.crictl_error(stderr : String, stdout : String = "") : String
    lines = stderr.lines.map(&.strip).reject(&.empty?).reject { |l| l =~ /\blevel=(warning|info|debug)\b/ }
    if error = lines.find { |l| l =~ /\blevel=(fatal|error)\b/ }
      if m = error.match(/\bmsg="((?:[^"\\]|\\.)*)"/)
        return m[1].gsub(%q(\"), %q("))
      end
      return error
    end
    lines.first? || stdout.lines.map(&.strip).find { |l| !l.empty? } || "no output"
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

  #each_container_by_resource(resource, namespace) do | container_id, container_pid_on_node, node, container_proctree_statuses, container_status|
  # A container the block never sees (not started, not ready, not readable
  # on its node) is named in `not_inspected` with the reason, when given,
  # so the test can say why it has nothing to judge (#2824).
  def self.all_containers_by_resource?(resource, namespace, only_container_pids : Bool = false, include_proctree : Bool = true, include_zombies : Bool = false, not_inspected : Array(String)? = nil, &block) 
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
					node = nodes.first? # there should only be one node returned for one pod
					node_name = pod.dig?("spec", "nodeName").try(&.as_s?) || "none"
					container_status_result = container_statuses.map do |container_status|
						container_name = container_status.dig("name")
						previous_process_type = "initial_name"
						# A container that has not started yet (its pod still Pending, an init
						# container running) has no ID: it is skipped like one that is not ready.
						label = "#{resource[:kind]}/#{resource[:name]} pod #{pod_name} container #{container_name}"
						unless node
							not_inspected.try(&.<< "#{label}: the pod's node (#{node_name}) could not be found")
							next
						end
						prefix_container_id = container_status.dig?("containerID").try(&.as_s?)
						unless prefix_container_id
							Log.debug { "no containerID yet, skipping: #{container_name} in #{pod_name}" }
							waiting = container_status.dig?("state", "waiting", "reason").try(&.as_s?)
							not_inspected.try(&.<< "#{label}: not started#{waiting ? " (#{waiting})" : ""}")
							next
						end
						container_id = strip_runtime_prefix(prefix_container_id)
						Log.debug { "before ready containerStatuses container_id #{container_id}" }
						ready = container_status.dig("ready").as_bool
						if !ready
							Log.debug { "container status: #{container_status} "}
							Log.debug { "not ready! skipping: containerStatuses container_id #{container_id}" }
							state = container_status["state"]?.try(&.as_h?).try(&.keys.first?)
							detail = container_status.dig?("state", "waiting", "reason").try(&.as_s?) || container_status.dig?("state", "terminated", "reason").try(&.as_s?)
							not_inspected.try(&.<< "#{label}: not ready#{state ? " (#{state}#{detail ? ": #{detail}" : ""})" : ""}")
							false
							next
						end
						# next unless ready 
						Log.debug { "containerStatuses container_id #{container_id}" }
						#get container id's pid on the node (different from inside the container)
						looked_up = ClusterTools.pid_or_reason(container_id, node)
						container_pid_on_node = looked_up[:pid].to_s
						if container_pid_on_node.empty?
							Log.debug { "no pid for (skipping): containerStatuses container_id #{container_id}" }
							not_inspected.try(&.<< "#{label}: #{looked_up[:reason]}")
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
                not_inspected.try(&.<< "#{label}: no process of the container could be listed on node #{node_name}")
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
          # No container status yet (the pod is Pending): its containers are
          # named from the spec, so a verdict on the other pods doesn't hide them.
          phase = status["phase"]?.try(&.as_s?) || "unknown"
          (pod.dig?("spec", "containers").try(&.as_a?) || [] of JSON::Any).each do |c|
            not_inspected.try(&.<< "#{resource[:kind]}/#{resource[:name]} pod #{pod_name} container #{c["name"]?}: not started (pod #{phase}, no container status yet)")
          end
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
    KubectlClient::Wait.resource_wait_for_install("Daemonset", "cluster-tools", namespace: self.namespace!, wait_count: 300)
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
  def self.image_tags(repository : String, plain_http : Bool = false) : Array(String)?
    result = exec("skopeo list-tags #{skopeo_creds}#{plain_http ? " --tls-verify=false" : ""} docker://#{repository}")
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
