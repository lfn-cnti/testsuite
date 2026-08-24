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

  # Node the workload identified by `deployment_label=deployment_value` sits on,
  # or nil when it has no pod scheduled anywhere.
  def self.get_workload_node_name(deployment_label, deployment_value, namespace) : String?
    scheduled_pod_node_name(namespace, "#{deployment_label}=#{deployment_value}")
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

  private def self.get_status_info_until(chaos_resource, test_name, output_format, timeout, namespace, &block)
    repeat_with_timeout(timeout: timeout, errormsg: "Litmus response timed-out") do
      status_code, status_response = get_status_info(chaos_resource, test_name, output_format, namespace)
      status_code == 0 && yield status_response
    end
  end

  ## wait_for_test will wait for the completion of litmus test
  def self.wait_for_test(test_name, chaos_experiment_name, args, namespace : String = "default")
    chaos_result_name = "#{test_name}-#{chaos_experiment_name}"
    Log.info { "wait_for_test: #{chaos_result_name}" }

    get_status_info_until("chaosengine", test_name, "jsonpath={.status.engineStatus}", LITMUS_CHAOS_TEST_TIMEOUT, namespace) do |engineStatus|
      ["completed", "stopped"].includes?(engineStatus)
    end

    get_status_info_until("chaosresults", chaos_result_name, "jsonpath={.status.experimentStatus.verdict}", GENERIC_OPERATION_TIMEOUT, namespace) do |verdict|
      verdict != "Awaited"
    end
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
