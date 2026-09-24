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



  def self.add_node_selector(node_name)
    file = File.read(downloaded_operator_file)
    deploy_index = file.index("kind: Deployment") || 0 
    spec_literal = "spec:"
    template = "\n      nodeSelector:\n        kubernetes.io/hostname: #{node_name}"
    spec1_index = file.index(spec_literal, deploy_index + 1)  || 0
    spec2_index = file.index(spec_literal, spec1_index + 1) || 0
    output_file = file.insert(spec2_index + spec_literal.size, template) unless spec2_index == 0
    File.write(modified_operator_file, output_file) unless output_file == nil
  end

  # Label pair that selects exactly the pods of `resource`, so a chaos engine
  # appinfo targets this workload and not every pod sharing a broad selector.
  # A selector like app.kubernetes.io/instance=<release> matches a whole Helm
  # release, which made pod-io-stress stress a random free5gc pod instead of
  # the tested deployment. When several selector labels exist, the first pair
  # whose value is carried by exactly the resource's own pods (owner-ref match)
  # wins. Falls back to the first selector label pair -- the historical
  # behavior -- when no pair resolves uniquely or when there is a single one.
  def self.resource_target_label(resource : NamedTuple(kind: String, name: String, namespace: String)) : {String, String}
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

    ordered.each do |key, value|
      key_s = key.to_s
      value_s = value.as_s
      matching = items.count do |pod|
        pod.dig?("metadata", "labels", key_s).try(&.as_s?) == value_s
      end
      # Require a strictly positive population so a scaled-to-zero workload (or
      # an unresolved backend) never "uniquely selects" a label no pod carries.
      if owned_size > 0 && matching == owned_size
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

  # Node the Litmus operator sits on, or nil when it is not scheduled anywhere.
  def self.get_litmus_node_name : String?
    scheduled_pod_node_name(LITMUS_NAMESPACE, "app.kubernetes.io/name=litmus")
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
  def self.check_chaos_verdict(chaos_result_name, chaos_experiment_name, args,
                               namespace : String = "default",
                               result : CNFManager::TestCaseResult? = nil) : Bool
    _, verdict = get_status_info("chaosresult", chaos_result_name, "jsonpath={.status.experimentStatus.verdict}", namespace)
    return true if verdict == "Pass"

    # The chaosresult knows *why*: surface its failStep and failed probes into
    # the test's details and the error log, instead of discarding them at a log
    # level no CI run has enabled. A verdict without its reason cost a full
    # afternoon of inference the one time node_drain flaked (#2445-adjacent).
    logger = Log.for("LitmusManager.check_chaos_verdict")
    status_code, raw_chaos_result = get_status_info("chaosresult", chaos_result_name, "json", namespace)
    failure = status_code == 0 ? chaos_failure_summary(raw_chaos_result) : nil
    summary = "#{chaos_experiment_name} verdict: #{verdict}#{failure ? " -- #{failure}" : ""}"

    logger.error { "#{chaos_result_name}: #{summary}" }
    result.try(&.append_description("Litmus #{summary}"))
    false
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

  # Runtime name and socket path the litmus chaos helpers need to exec into a
  # target container, derived from a node's containerRuntimeVersion (e.g.
  # "containerd://2.0.2"). Returns nil when the runtime is not one the helpers
  # understand, in which case the caller should skip rather than ship the
  # default containerd values into an incompatible cluster.
  def self.runtime_socket_for(container_runtime : String) : {String, String}?
    name = container_runtime.split("://", 2).first.strip.downcase
    case name
    when "docker"
      {"docker", "/var/run/docker.sock"}
    when "containerd"
      {"containerd", "/run/containerd/containerd.sock"}
    when "crio", "cri-o"
      {"crio", "/var/run/crio/crio.sock"}
    else
      nil
    end
  end

  # {runtime, socket_path} for the cluster, from the first node whose container
  # runtime is supported, or nil when none of them is. The chaos engine must
  # not arm the experiment with a hard-coded containerd socket on a docker or
  # cri-o cluster: the litmus helper would be unable to reach the runtime at
  # injection time and would report a runtime error.
  def self.detect_runtime_socket : {String, String}?
    runtimes = KubectlClient::Get.container_runtimes
    runtimes.each do |runtime|
      resolved = runtime_socket_for(runtime)
      return resolved if resolved
    end
    Log.for("LitmusManager.detect_runtime_socket").warn { "Unsupported container runtime(s) for chaos injection: #{runtimes.join(", ")}" }
    nil
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
end
