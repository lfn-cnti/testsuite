module LitmusManager

  # renovate: datasource=github-tags depName=litmuschaos/chaos-charts
  Version = "3.31.0"
  CHAOS_CHARTS = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{Version}"
  NODE_LABEL = "kubernetes.io/hostname"
  #https://raw.githubusercontent.com/litmuschaos/chaos-operator/v2.14.x/deploy/operator.yaml
  LITMUS_OPERATOR = "https://litmuschaos.github.io/litmus/litmus-operator-v#{LitmusManager::Version}.yaml"
  # for node drain; live with the chaos templates, not in the CWD
  def self.downloaded_operator_file : String
    File.join(chaos_manifests_path, "litmus-operator-downloaded.yaml")
  end

  def self.modified_operator_file : String
    File.join(chaos_manifests_path, "litmus-operator-modified.yaml")
  end
  LITMUS_NAMESPACE = "litmus"
  LITMUS_K8S_DOMAIN = "litmuschaos.io"



  # Label pair that selects exactly the pods of `resource`, so a chaos engine
  # appinfo targets this workload and not every pod sharing a broad selector.
  # A selector like app.kubernetes.io/instance=<release> matches a whole Helm
  # release, which made pod-io-stress stress a random free5gc pod instead of
  # the tested deployment. When several selector labels exist, the first pair
  # whose value is carried by exactly the resource's own pods (owner-ref match)
  # wins. Falls back to the first selector label pair -- the historical
  # behavior -- when no pair resolves uniquely or when there is a single one,
  # and returns nil when the resource owns no pod at all.
  def self.resource_target_label(resource : NamedTuple(kind: String, name: String, namespace: String)) : {String, String}?
    logger = Log.for("LitmusManager.resource_target_label")
    selector_labels = KubectlClient::Get.resource_spec_labels(resource[:kind], resource[:name], resource[:namespace])
    labels = selector_labels.as_h?
    unless labels && !labels.empty?
      logger.info { "No selector label for #{resource[:kind]}/#{resource[:name]}; targeting app.kubernetes.io/name=#{resource[:name]}" }
      return {"app.kubernetes.io/name", resource[:name]}
    end

    ordered = labels.to_a
    return {ordered[0][0].to_s, ordered[0][1].as_s} if ordered.size == 1

    pods = KubectlClient::Get.resource("pods", namespace: resource[:namespace])
    items = pods.dig?("items").try(&.as_a) || [] of JSON::Any

    # A Deployment's pods are owned by a ReplicaSet, not by the Deployment
    # itself, so comparing ownerReferences against the resource uid directly
    # always yields zero owned pods for Deployments: every label then "matches"
    # in a namespace-wide sense and the engine falls back to a broad selector
    # (e.g. app.kubernetes.io/instance=<release>) under which the litmus helper
    # stresses a random pod of the whole release. Resolve the owned pod set
    # through the descendant tree (Deployment -> ReplicaSet -> Pod, but also
    # StatefulSet/DaemonSet/Job which own their pods directly) instead.
    owned_pod_uids = Set(String).new
    KubectlClient::Get.descendants(resource[:kind], resource[:name], resource[:namespace]).each do |descendant|
      owned_pod_uids.add(descendant[:uid]) if descendant[:kind].downcase == "pod"
    end
    owned_size = items.count do |pod|
      pod_uid = pod.dig?("metadata", "uid").try(&.as_s?)
      pod_uid && owned_pod_uids.includes?(pod_uid)
    end

    # A workload that owns no pod (scaled to zero, or a backend that never
    # came up) has nothing to target: a broad fallback selector would stress
    # a random pod of the release instead.
    if owned_size == 0
      logger.warn { "#{resource[:kind]}/#{resource[:name]} owns no pod; nothing to target" }
      return nil
    end

    ordered.each do |key, value|
      key_s = key.to_s
      value_s = value.as_s
      matching = items.count do |pod|
        pod.dig?("metadata", "labels", key_s).try(&.as_s?) == value_s
      end
      if matching == owned_size
        logger.info { "Targeting #{resource[:kind]}/#{resource[:name]} with #{key_s}=#{value_s} (#{matching} pod(s))" }
        return {key_s, value_s}
      end
    end

    logger.warn { "No uniquely selecting label for #{resource[:kind]}/#{resource[:name]}; falling back to #{ordered[0][0]}=#{ordered[0][1]}" }
    {ordered[0][0].to_s, ordered[0][1].as_s}
  end

  # Node the workload identified by `deployment_label=deployment_value` sits on,
  # or nil when it has no pod scheduled anywhere.
  # Node of the workload matching `selector` (a `k=v[,k=v...]` label selector).
  def self.get_workload_node_name(selector : String, namespace) : String?
    scheduled_pod_node_name(namespace, selector)
  end

  # Node of the pod matching `selector`, or nil when none is scheduled.
  #
  # Terminating pods are excluded. They are still listed by `kubectl get pods` and
  # their phase is still Running, so only the deletion timestamp distinguishes
  # them -- and the node one of them names is a node its workload is already
  # leaving, which sends the caller to the wrong node moments later.
  #
  # A pod that is scheduled but still starting does count: it is already bound to
  # its node. A Running pod is preferred when the selector matches several.
  private def self.scheduled_pod_node_name(namespace : String, selector : String) : String?
    logger = Log.for("scheduled_pod_node_name")
    pods = KubectlClient::Get.resource("pods", namespace: namespace, selector: selector)
    items = pods.dig?("items").try(&.as_a) || [] of JSON::Any
    scheduled_pods = items.select do |pod|
      pod.dig?("metadata", "deletionTimestamp").nil? && pod.dig?("spec", "nodeName")
    end
    pod = scheduled_pods.find { |p| p.dig?("status", "phase").try(&.as_s) == "Running" } || scheduled_pods.first?
    node_name = pod.try(&.dig?("spec", "nodeName")).try(&.as_s)
    logger.info { "Selector '#{selector}' in #{namespace} namespace matched #{items.size} pod(s), #{scheduled_pods.size} of them scheduled and not terminating; node: #{node_name || "none"}" }
    node_name
  end

  private def self.get_status_info(chaos_resource, test_name, output_format, namespace) : {Int32, String}
    status_cmd = "kubectl get #{chaos_resource}.#{LITMUS_K8S_DOMAIN} #{test_name} -n #{namespace} -o '#{output_format}'"
    Log.info { "Getting litmus status info: #{status_cmd}" }
    status_code = Process.run("#{status_cmd}", shell: true, output: status_response = IO::Memory.new, error: stderr = IO::Memory.new).exit_code
    status_response = status_response.to_s
    Log.info { "status_code: #{status_code}, response: #{status_response}" }
    {status_code, status_response}
  end

  private def self.get_status_info_until(chaos_resource, test_name, output_format, timeout, namespace, status : String? = nil, &block)
    started = Time.utc
    last_tick = started
    repeat_with_timeout(timeout: timeout, errormsg: "Litmus response timed-out") do
      if status
        elapsed = (Time.utc - started).to_i
        # Every poll on a TTY (the line rewrites itself); every 30 s when piped,
        # so CI logs get a heartbeat without a line per poll.
        if STDOUT.tty? || (Time.utc - last_tick) >= 30.seconds
          StatusLine.update "#{status} (#{elapsed}s of #{timeout}s)..."
          last_tick = Time.utc
        end
      end
      status_code, status_response = get_status_info(chaos_resource, test_name, output_format, namespace)
      status_code == 0 && yield status_response
    end
  end

  ## wait_for_test will wait for the completion of litmus test
  def self.wait_for_test(test_name, chaos_experiment_name, args, namespace : String = "default")
    chaos_result_name = "#{test_name}-#{chaos_experiment_name}"
    Log.info { "wait_for_test: #{chaos_result_name}" }
    status = "Waiting for the #{chaos_experiment_name} chaos experiment to finish"
    StatusLine.push "#{status}..."

    get_status_info_until("chaosengine", test_name, "jsonpath={.status.engineStatus}", LITMUS_CHAOS_TEST_TIMEOUT, namespace, status) do |engineStatus|
      ["completed", "stopped"].includes?(engineStatus)
    end

    get_status_info_until("chaosresults", chaos_result_name, "jsonpath={.status.experimentStatus.verdict}", GENERIC_OPERATION_TIMEOUT, namespace, "Waiting for the #{chaos_experiment_name} verdict") do |verdict|
      verdict != "Awaited"
    end
    StatusLine.pop
  end

  ## check_chaos_verdict will check the verdict of chaosexperiment
  # Every run leaves one details line: the experiment, the workload it ran
  # on, the verdict, the pods litmus targeted and how long the engine ran,
  # so a pass is auditable and a failure names the pod (#2601).
  def self.check_chaos_verdict(chaos_result_name, chaos_experiment_name, args,
                               namespace : String = "default",
                               result : CNFManager::TestCaseResult? = nil,
                               target : String? = nil) : Bool
    logger = Log.for("LitmusManager.check_chaos_verdict")
    _, verdict = get_status_info("chaosresult", chaos_result_name, "jsonpath={.status.experimentStatus.verdict}", namespace)
    passed = verdict == "Pass"

    status_code, raw_chaos_result = get_status_info("chaosresult", chaos_result_name, "json", namespace)
    raw_chaos_result = "" unless status_code == 0
    engine_name = chaos_result_name.to_s.rchop("-#{chaos_experiment_name}")
    status_code, raw_engine = get_status_info("chaosengine", engine_name, "json", namespace)
    raw_engine = "" unless status_code == 0

    # The chaosresult knows *why*: surface its failStep and failed probes into
    # the test's details and the error log, instead of discarding them at a log
    # level no CI run has enabled. A verdict without its reason cost a full
    # afternoon of inference the one time node_drain flaked (#2445-adjacent).
    failure = passed ? nil : chaos_failure_summary(raw_chaos_result)
    summary = "#{chaos_experiment_name}#{target ? " on #{target}" : ""}: verdict #{verdict}#{failure ? " -- #{failure}" : ""}; #{chaos_run_summary(raw_chaos_result, raw_engine)}"

    passed ? logger.info { "#{chaos_result_name}: #{summary}" } : logger.error { "#{chaos_result_name}: #{summary}" }
    result.try(&.append_description("Litmus #{summary}"))
    passed
  end

  # What litmus reports having targeted (chaosresult status.history.targets:
  # the app the engine was pointed at, by name and kind, with its chaos
  # status) and how long the engine ran (its creation to the experiment's
  # last update), as one phrase for the details line.
  def self.chaos_run_summary(raw_chaos_result : String, raw_engine : String) : String
    targets = [] of String
    begin
      JSON.parse(raw_chaos_result).dig?("status", "history", "targets").try(&.as_a?).try &.each do |t|
        name = t["name"]?.try(&.as_s?)
        next if name.nil? || name.empty?
        kind = t["kind"]?.try(&.as_s?)
        status = t["chaosStatus"]?.try(&.as_s?)
        targets << "#{kind ? "#{kind} " : ""}#{name}#{status ? " (#{status})" : ""}"
      end
    rescue JSON::ParseException
    end
    duration = nil.as(Int64?)
    begin
      engine = JSON.parse(raw_engine)
      created = engine.dig?("metadata", "creationTimestamp").try(&.as_s?)
      finished = engine.dig?("status", "experiments").try(&.as_a?).try(&.compact_map { |e| e["lastUpdateTime"]?.try(&.as_s?) }.max?)
      duration = (Time.parse_rfc3339(finished) - Time.parse_rfc3339(created)).total_seconds.to_i64 if created && finished
    rescue JSON::ParseException | Time::Format::Error
    end
    what = targets.empty? ? "target not recorded by litmus" : "target #{targets.join(", ")}"
    duration ? "#{what}, engine ran #{duration} s" : what
  end

  # Distills a chaosresult JSON into the line a human needs: the step that
  # failed and every probe that did not pass. Returns nil when the payload
  # holds no such detail (or is not JSON at all).
  def self.chaos_failure_summary(raw_chaos_result : String) : String?
    json = JSON.parse(raw_chaos_result)
    parts = [] of String

    fail_step = json.dig?("status", "experimentStatus", "failStep").try(&.as_s?)
    parts << "failStep: #{fail_step}" if fail_step && !fail_step.empty? && fail_step != "N/A"

    json.dig?("status", "probeStatuses").try(&.as_a?).try &.each do |probe|
      probe_verdict = probe.dig?("status", "verdict").try(&.as_s?)
      next if probe_verdict.nil? || probe_verdict == "Passed"
      name = probe.dig?("name").try(&.as_s?) || "unnamed"
      description = probe.dig?("status", "description").try(&.as_s?)
      parts << "probe #{name}: #{probe_verdict}#{description ? " (#{description})" : ""}"
    end

    parts.empty? ? nil : parts.join("; ")
  rescue JSON::ParseException
    nil
  end

  # Name of the first application container a root-filesystem fault
  # (disk_fill's `dd`, pod_io_stress's `fio`) can be injected into, or nil when
  # every container mounts a read-only root file system. Both litmus helpers
  # write a file into the target container's root file system, so a read-only
  # one makes the injection fail in ChaosInject ("Read-only file system" /
  # "exit status 1"); and both default to the pod's first container, so the
  # engine must name a writable one explicitly.
  def self.filesystem_fault_target(containers : JSON::Any) : String?
    containers.as_a.each do |container|
      read_only = container.dig?("securityContext", "readOnlyRootFilesystem").try(&.as_bool?)
      return container["name"].as_s unless read_only == true
    end
    nil
  end

  # Host socket paths through which the litmus chaos helpers reach a container
  # runtime, most common first. Distributions move the containerd socket: k3s
  # and RKE2 keep it under /run/k3s, microk8s under its snap directory.
  RUNTIME_SOCKET_CANDIDATES = {
    "docker"     => ["/var/run/docker.sock"],
    "containerd" => ["/run/containerd/containerd.sock", "/run/k3s/containerd/containerd.sock", "/var/snap/microk8s/common/run/containerd.sock"],
    "crio"       => ["/var/run/crio/crio.sock"],
  }

  # Overrides the detected socket path for clusters that keep it elsewhere. A
  # cluster property, so an environment variable and not the CNF's config.
  RUNTIME_SOCKET_ENV = "CNTI_TESTSUITE_CONTAINER_RUNTIME_SOCKET"

  POD_IO_STRESS_MEMORY_BUDGET_FRACTION = ENV["CNTI_TESTSUITE_POD_IO_STRESS_MEMORY_BUDGET_FRACTION"]?.try(&.to_f64?) || 0.5_f64

  # Preferred write path of the pod_io_stress file inside the target container.
  # The percentage bound is computed from the live free space of the exact path
  # the file lands on (see pod_io_stress_bound), so the two always match. A CNF
  # or cluster that wants the stress somewhere specific (e.g. a bigger emptyDir)
  # can pin that path; by default the container's /dev/shm tmpfs is used because
  # it is bounded (~64 MiB by default) and memory-accounted, so a percentage of
  # it is always expressible and stays under every memory quota.
  POD_IO_STRESS_VOLUME_MOUNT_PATH = ENV["CNTI_TESTSUITE_POD_IO_STRESS_VOLUME_MOUNT_PATH"]?.presence || "/dev/shm"

  # Candidates probed when the env override is not set, in priority order: a
  # bounded tmpfs first (memory-charged, so the stress exercises the memory
  # wall the bound protects), then /tmp, then the container root; "/" is always
  # present since pod_io_stress only targets a writable root file system.
  POD_IO_STRESS_VOLUME_MOUNT_PATH_CANDIDATES = ["/dev/shm", "/tmp", "/"] of String

  # Runtime name the litmus helpers understand, from a node's
  # containerRuntimeVersion (e.g. "containerd://2.0.2"), or nil.
  def self.runtime_name(container_runtime : String) : String?
    case container_runtime.split("://", 2).first.strip.downcase
    when "docker"        then "docker"
    when "containerd"    then "containerd"
    when "crio", "cri-o" then "crio"
    end
  end

  # Runtime name and its usual socket path, or nil for a runtime the helpers
  # do not understand; the caller should skip rather than ship containerd
  # defaults into an incompatible cluster.
  def self.runtime_socket_for(container_runtime : String) : {String, String}?
    name = runtime_name(container_runtime)
    name ? {name, RUNTIME_SOCKET_CANDIDATES[name].first} : nil
  end

  # The cluster's runtime name, from the first node whose runtime the helpers
  # understand, or nil when none of them is.
  def self.detect_runtime(runtimes : Array(String) = KubectlClient::Get.container_runtimes) : String?
    name = runtimes.compact_map { |runtime| runtime_name(runtime) }.first?
    Log.for("LitmusManager.detect_runtime").warn { "Unsupported container runtime(s) for chaos injection: #{runtimes.join(", ")}" } unless name
    name
  end

  # Host path of the runtime's socket: the environment override when set,
  # otherwise the first candidate that exists on a node, probed through the
  # cluster-tools DaemonSet, which mounts the node's root file system at
  # /host. Nil when none is found.
  def self.detect_runtime_socket(runtime : String) : String?
    logger = Log.for("LitmusManager.detect_runtime_socket")
    if (override = ENV[RUNTIME_SOCKET_ENV]?) && !override.empty?
      logger.info { "Using #{RUNTIME_SOCKET_ENV}=#{override} for #{runtime}" }
      return override
    end

    candidates = RUNTIME_SOCKET_CANDIDATES[runtime]
    node = KubectlClient::Get.schedulable_nodes_list.first?
    unless node
      logger.warn { "No schedulable node to probe for the #{runtime} socket" }
      return nil
    end
    probe = "sh -c 'for p in #{candidates.join(" ")}; do [ -S \"/host$p\" ] && echo \"$p\" && exit 0; done; exit 1'"
    found = ClusterTools.exec_by_node(probe, node)[:output].strip
    if found.empty?
      logger.warn { "No #{runtime} socket on #{node.dig?("metadata", "name")} among #{candidates.join(", ")}; set #{RUNTIME_SOCKET_ENV}" }
      return nil
    end
    logger.info { "#{runtime} socket found at #{found}" }
    found
  end

  def self.chaos_manifests_path
    Log.info {"chaos_manifests_path"}
    chaos_manifests = "#{tools_path}/chaos-experiments"
    if !Dir.exists?(chaos_manifests)
      FileUtils.mkdir_p(chaos_manifests)
    end
    chaos_manifests
  end

  # Install a LitmusChaos fault into the CNF's namespace: the ChaosExperiment
  # from chaos-charts at LitmusManager::Version, and the fault's service
  # account, role and binding embedded in the binary. Returns the path of the
  # downloaded experiment manifest.
  def self.install_fault(fault : String, namespace : String, task_name : String) : String
    experiment_path = download_template("#{CHAOS_CHARTS}/faults/kubernetes/#{fault}/fault.yaml", "#{task_name}_experiment.yaml")
    KubectlClient::Apply.file(experiment_path, namespace: namespace)

    rbac_path = "#{chaos_manifests_path}/#{task_name}_rbac.yaml"
    File.write(rbac_path, LITMUS_RBAC[fault].gsub("namespace: default", "namespace: #{namespace}"))
    KubectlClient::Apply.file(rbac_path)

    experiment_path
  end

  def self.download_template(url, filename)
    Log.info {"download_template url, filename: #{url}, #{filename}"}
    cmp = chaos_manifests_path()
    filepath = "#{cmp}/#{filename}"
    Log.info {"filepath: #{filepath}"}

    download_file(url, filepath)

    filepath
  end

  def self.container_memory_limit_bytes(containers : JSON::Any, container_name : String) : Int64?
    containers.as_a.each do |container|
      next unless container["name"]?.try(&.as_s?) == container_name
      limit = container.dig?("resources", "limits", "memory").try(&.as_s?)
      return memory_quantity_bytes(limit) if limit
    end
    nil
  end

  def self.memory_quantity_bytes(quantity : String) : Int64?
    match = quantity.strip.match(/\A(\d+)\s*(Ki|Mi|Gi|Ti|Pi|Ei|K|M|G|T|P|E)?\z/i)
    return nil unless match
    factor = case match[2]?.try(&.downcase)
             when nil     then 1_i64
             when "ki"    then 1024_i64
             when "mi"    then 1024_i64 ** 2
             when "gi"    then 1024_i64 ** 3
             when "ti"    then 1024_i64 ** 4
             when "pi"    then 1024_i64 ** 5
             when "ei"    then 1024_i64 ** 6
             when "k"     then 1000_i64
             when "m"     then 1000_i64 ** 2
             when "g"     then 1000_i64 ** 3
             when "t"     then 1000_i64 ** 4
             when "p"     then 1000_i64 ** 5
             when "e"     then 1000_i64 ** 6
             else              1_i64
             end
    match[1].to_i64 * factor
  end

  # A percentage a stress-ng "--hdd-bytes" accepts that yields a 1 MiB file
  # (stress-ng floors fractional percentages and then clamps to its 1.0 MB
  # MIN_HDD_BYTES). Emitted whenever the budget needs less than a full percent
  # of the free space, since stress-ng has no way to size a file between 0 and
  # 1% of the filesystem.
  def self.min_percentage
    "0.5"
  end

  # Free space, in bytes, of a path as the target container sees it. The litmus
  # pod_io_stress helper runs stress-ng inside the target container and
  # stress-ng sizes its file as a percentage of the free space of the
  # --temp-path filesystem (f_bavail * f_bsize via statvfs). The bound is only
  # trustworthy if it is computed from that same path and filesystem, so it is
  # probed through the cluster-tools DaemonSet: /proc/<pid>/root resolves the
  # path into the target container's root, bypassing the container's own
  # binaries which a minimal image may lack.
  def self.filesystem_free_space_bytes(
    container_pid_on_node : String,
    node : JSON::Any,
    volume_mount_path : String
  ) : Int64?
    result = ClusterTools.exec_by_node("stat -f -c '%S %a' /proc/#{container_pid_on_node}/root#{volume_mount_path}", node)
    return nil unless result && result[:status].success?
    block_size, free_blocks = result[:output].strip.split
    block_size.to_i64? && free_blocks.to_i64? ? block_size.to_i64 * free_blocks.to_i64 : nil
  rescue error : Exception
    Log.for("LitmusManager.filesystem_free_space_bytes").error { "probe of #{volume_mount_path} in container #{container_pid_on_node} on node #{node.dig?("metadata", "name")} failed: #{error.message}" }
    nil
  end

  # Whether a path sits on a tmpfs: its pages are memory-backed and charged as
  # shmem to the target container's memory cgroup, the accounting that made the
  # original 10% default file blow the NFs' memory limits.
  def self.filesystem_tmpfs?(container_pid_on_node : String, node : JSON::Any, volume_mount_path : String) : Bool
    result = ClusterTools.exec_by_node("stat -f -c '%T' /proc/#{container_pid_on_node}/root#{volume_mount_path}", node)
    result && result[:status].success? && result[:output].strip == "tmpfs"
  rescue error : Exception
    Log.for("LitmusManager.filesystem_tmpfs?").error { "type probe of #{volume_mount_path} in container #{container_pid_on_node} failed: #{error.message}" }
    false
  end

  # The id of the container named container_name on its node, from the
  # cluster-tools DaemonSet (which already tracks every container's node pid).
  def self.target_container_pid_on_node(resource, namespace : String, container_name : String) : {String, JSON::Any}?
    found : {String, JSON::Any}? = nil
    ClusterTools.all_containers_by_resource?(resource, namespace, include_proctree: false) do |_, container_pid_on_node, node, _, container_status, _|
      next unless container_status.dig?("name").try(&.as_s?) == container_name
      found = {container_pid_on_node, node}
      break
    end
    found
  end

  # A path the stress file can be written to inside the target container,
  # honoring the CNTI_TESTSUITE_POD_IO_STRESS_VOLUME_MOUNT_PATH override
  # verbatim; by default the reachable candidate with the smallest bounded
  # filesystem is preferred (tmpfs first), so the percentage bound stays
  # expressible.
  def self.pod_io_stress_volume_mount_path(container_pid_on_node : String, node : JSON::Any) : String
    candidates = if ENV.has_key?("CNTI_TESTSUITE_POD_IO_STRESS_VOLUME_MOUNT_PATH")
                   [POD_IO_STRESS_VOLUME_MOUNT_PATH] of String
                 else
                   POD_IO_STRESS_VOLUME_MOUNT_PATH_CANDIDATES
                 end
    tmpfs_paths = candidates.select do |path|
      filesystem_tmpfs?(container_pid_on_node, node, path) && filesystem_free_space_bytes(container_pid_on_node, node, path)
    end
    return tmpfs_paths.first unless tmpfs_paths.empty?

    disk_paths = candidates.select { |path| filesystem_free_space_bytes(container_pid_on_node, node, path) }
    disk_paths.first? || candidates.first
  end

  # Percentage of the chosen write path's free space that keeps the
  # pod_io_stress file under the container's memory budget (quota times
  # POD_IO_STRESS_MEMORY_BUDGET_FRACTION), together with that exact path so the
  # engine can pin VOLUME_MOUNT_PATH to it. stress-ng computes "N% of free
  # space" as N * free / 100, so the floor of budget * 100 / free keeps the
  # file at or under the budget. Nil when the container has no memory limit
  # (nothing to protect); on a probe failure it degrades to the smallest
  # percentage rather than returning an unbounded one, which would reintroduce
  # the OOM race this bound exists to prevent.
  def self.pod_io_stress_bound(containers : JSON::Any, resource, namespace : String, container_name : String) : NamedTuple(percentage: String, volume_mount_path: String)?
    budget = container_memory_limit_bytes(containers, container_name)
    return nil unless budget
    logger = Log.for("LitmusManager.pod_io_stress_bound")
    budget_bytes = (budget.to_f64 * POD_IO_STRESS_MEMORY_BUDGET_FRACTION).to_i64

    found = target_container_pid_on_node(resource, namespace, container_name)
    unless found
      logger.warn { "target container #{container_name} not found on any node, degrading the io stress file to #{min_percentage}%" }
      return {percentage: min_percentage, volume_mount_path: ""}
    end
    pid_on_node, node = found

    volume_mount_path = pod_io_stress_volume_mount_path(pid_on_node, node)
    free_space_bytes = filesystem_free_space_bytes(pid_on_node, node, volume_mount_path)
    unless free_space_bytes && free_space_bytes > 0
      logger.warn { "cannot read free space of #{volume_mount_path} in #{container_name}, degrading the io stress file to #{min_percentage}%" }
      return {percentage: min_percentage, volume_mount_path: ""}
    end

    # Floor, not ceil: a percentage above budget * 100 / free would write a
    # file above the budget and bring the OOM race back (e.g. 1% of a 7.5 GiB
    # root fs is 77 MiB, larger than dbpython's 64 MiB budget).
    integer_percentage = (budget_bytes * 100) // free_space_bytes
    percentage = if integer_percentage < 1
                   min_percentage
                 else
                   {integer_percentage, 90}.min
                 end
    logger.info { "#{container_name}: memory budget ~#{budget_bytes // 1024 // 1024} MiB over #{free_space_bytes // 1024 // 1024} MiB free at #{volume_mount_path}, io stress file set to #{percentage}%" }
    {percentage: percentage.to_s, volume_mount_path: volume_mount_path}
  end
end
