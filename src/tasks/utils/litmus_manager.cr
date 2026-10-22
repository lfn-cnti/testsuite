module LitmusManager

  # renovate: datasource=github-tags depName=litmuschaos/chaos-charts
  Version = "3.31.0"
  # Where the fault templates come from; CNTI_TESTSUITE_CHAOS_CHARTS_URL names
  # a mirror of the chaos-charts tree (the same layout, faults/kubernetes/...).
  CHAOS_CHARTS_ENV = "CNTI_TESTSUITE_CHAOS_CHARTS_URL"
  CHAOS_CHARTS = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{Version}"

  # Without a trailing slash: the fault paths are appended with their own.
  def self.chaos_charts : String
    (ENV[CHAOS_CHARTS_ENV]?.presence || CHAOS_CHARTS).rstrip('/')
  end

  # Raised when a fault's template could not be fetched (after the network
  # retries) or its experiment could not be applied: the test has nothing to
  # inject and ends SKIPPED with this message, not ERROR (#2832).
  class FaultInstallError < Exception
    def initialize(fault : String, step : String, reason : String)
      super("litmus fault #{fault} could not be #{step}: #{reason}")
    end
  end
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

  # Name of the chaos engine of one experiment on one workload. The suffix
  # is random and long enough to be unique: a number below 99 repeated within
  # a run, and the second test then reused the engine of the first (#2670).
  def self.engine_name(workload_name : String) : String
    "#{workload_name}-#{Random::Secure.hex(4)}"
  end

  ## wait_for_test will wait for the completion of litmus test
  # Returns false when litmus skipped the experiment: the runner found no
  # experiment to run (ChaosExperiment missing, its job not created, ...), so
  # there is no experiment pod and never a ChaosResult. Waiting for the
  # verdict then would only cost the timeout (#2731).
  def self.wait_for_test(test_name, chaos_experiment_name, args, namespace : String = "default") : Bool
    chaos_result_name = "#{test_name}-#{chaos_experiment_name}"
    Log.info { "wait_for_test: #{chaos_result_name}" }
    # A stop while the experiment runs deletes the engine, and with it the
    # fault litmus injected (#2713).
    RunStop.register("chaosengine #{test_name} in #{namespace}") { delete_engine(test_name, namespace) }
    status = "Waiting for the #{chaos_experiment_name} chaos experiment to finish"
    StatusLine.push "#{status}..."

    skipped = false
    get_status_info_until("chaosengine", test_name, "json", LITMUS_CHAOS_TEST_TIMEOUT, namespace, status) do |raw_engine|
      if skipped_experiment?(raw_engine)
        skipped = true
        true
      else
        ["completed", "stopped"].includes?(engine_status(raw_engine))
      end
    end

    if skipped
      Log.for("LitmusManager.wait_for_test").warn { "#{chaos_result_name}: litmus skipped the experiment, not waiting for a verdict" }
    else
      get_status_info_until("chaosresults", chaos_result_name, "jsonpath={.status.experimentStatus.verdict}", GENERIC_OPERATION_TIMEOUT, namespace, "Waiting for the #{chaos_experiment_name} verdict") do |verdict|
        verdict != "Awaited"
      end
    end
    StatusLine.pop
    !skipped
  end

  def self.engine_status(raw_engine : String) : String?
    JSON.parse(raw_engine).dig?("status", "engineStatus").try(&.as_s?)
  rescue JSON::ParseException
    nil
  end

  # The runner pod of an experiment the engine reports as skipped, nil when
  # no experiment is skipped (or the JSON is not an engine).
  def self.skipped_experiment?(raw_engine : String) : String?
    experiments = JSON.parse(raw_engine).dig?("status", "experiments").try(&.as_a?) || return nil
    skipped = experiments.find { |e| e["status"]?.try(&.as_s?) == "Skipped" } || return nil
    skipped["runner"]?.try(&.as_s?) || "#{JSON.parse(raw_engine).dig?("metadata", "name").try(&.as_s?)}-runner"
  rescue JSON::ParseException
    nil
  end

  # Why litmus skipped: the runner records it as an event on the engine
  # (reason ExperimentSkipped, ExperimentNotFound, JobCreationError, ...) and
  # in its own log, and the ChaosExperiment it looked for may be missing.
  # Every line is collected, none is required: this runs on a cluster where
  # something already went wrong.
  def self.skip_diagnostics(engine_name : String, runner : String, chaos_experiment_name : String, namespace : String) : Array(String)
    lines = [] of String
    begin
      events = KubectlClient::Get.resource("events", namespace: namespace)
      lines.concat(skip_events(events, engine_name, runner))
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      lines << "events of #{namespace} not readable: #{ex.message.to_s.lines.first?}"
    end
    begin
      KubectlClient::Get.resource("chaosexperiment.#{LITMUS_K8S_DOMAIN}", chaos_experiment_name, namespace)
      lines << "ChaosExperiment #{chaos_experiment_name} exists in #{namespace}"
    rescue KubectlClient::ShellCMD::NotFoundError
      lines << "ChaosExperiment #{chaos_experiment_name} not found in #{namespace}"
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      lines << "ChaosExperiment #{chaos_experiment_name}: #{ex.message.to_s.lines.first?}"
    end
    begin
      log = KubectlClient::Utils.logs(runner, namespace: namespace, options: "--tail=15")[:output].to_s.strip
      lines << "runner #{runner} log: #{log.empty? ? "(empty)" : log.lines.map(&.strip).join(" | ")}"
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      lines << "runner #{runner} log not available: #{ex.message.to_s.lines.first?}"
    end
    lines
  end

  # The events about the engine or its runner, newest last, as "reason: message".
  def self.skip_events(events : JSON::Any, engine_name : String, runner : String) : Array(String)
    items = events.dig?("items").try(&.as_a?) || [] of JSON::Any
    about = items.select do |e|
      name = e.dig?("involvedObject", "name").try(&.as_s?) || ""
      name == engine_name || name == runner
    end
    about = about.sort_by { |e| (e["lastTimestamp"]? || e["eventTime"]? || e.dig?("metadata", "creationTimestamp")).try(&.as_s?) || "" }
    about.map do |e|
      "event #{e.dig?("involvedObject", "kind").try(&.as_s?)}/#{e.dig?("involvedObject", "name").try(&.as_s?)}: #{e["reason"]?.try(&.as_s?)}: #{(e["message"]?.try(&.as_s?) || "").lines.first?.to_s.strip}"
    end.last(6)
  end

  # Experiments litmus skipped in the test under way, "<experiment> on
  # <target>: <why>"; read and cleared by the test's verdict.
  @@skipped_experiments = [] of String

  def self.take_skipped : Array(String)
    skipped = @@skipped_experiments
    @@skipped_experiments = [] of String
    skipped
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

    # Litmus skipped the experiment: nothing was injected, so the CNF was not
    # tested and the verdict is not its own. The test ends as an error with
    # the reason litmus gave (#2731).
    if (runner = skipped_experiment?(raw_engine))
      why = skip_diagnostics(engine_name, runner, chaos_experiment_name.to_s, namespace)
      summary = "#{chaos_experiment_name}#{target ? " on #{target}" : ""}: skipped by litmus, no experiment ran; #{chaos_run_summary(raw_chaos_result, raw_engine)}"
      logger.error { "#{chaos_result_name}: #{summary}; #{why.join("; ")}" }
      result.try do |r|
        r.append_description("Litmus #{summary}")
        why.each { |line| r.append_description("  #{line}") }
      end
      @@skipped_experiments << "#{chaos_experiment_name}#{target ? " on #{target}" : ""}#{why.first?.try { |w| " (#{w})" }}"
      delete_engine(engine_name, namespace)
      return false
    end

    # The chaosresult knows *why*: surface its failStep and failed probes into
    # the test's details and the error log, instead of discarding them at a log
    # level no CI run has enabled. A verdict without its reason cost a full
    # afternoon of inference the one time node_drain flaked (#2445-adjacent).
    failure = passed ? nil : chaos_failure_summary(raw_chaos_result)
    summary = "#{chaos_experiment_name}#{target ? " on #{target}" : ""}: verdict #{verdict}#{failure ? " -- #{failure}" : ""}; #{chaos_run_summary(raw_chaos_result, raw_engine)}"

    passed ? logger.info { "#{chaos_result_name}: #{summary}" } : logger.error { "#{chaos_result_name}: #{summary}" }
    result.try(&.append_description("Litmus #{summary}"))
    delete_engine(engine_name, namespace)
    passed
  end

  # The engine has done its work once the verdict is read. Left behind, the
  # engines of a run pile up in the CNF's namespace, with their runner pods.
  def self.delete_engine(engine_name : String, namespace : String)
    RunStop.done("chaosengine #{engine_name} in #{namespace}")
    KubectlClient::Delete.resource("chaosengine.#{LITMUS_K8S_DOMAIN}", engine_name, namespace)
  rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
    Log.for("LitmusManager.delete_engine").warn { "chaosengine #{engine_name} in #{namespace} not deleted: #{ex.message.to_s.lines.first?}" }
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

    # An experiment that could not run says why in errorOutput; its reason is
    # the helper's own report, as JSON in a string.
    if error = json.dig?("status", "experimentStatus", "errorOutput")
      code = error.dig?("errorCode").try(&.as_s?)
      reason = error.dig?("reason").try(&.as_s?)
      if reason
        begin
          helper = JSON.parse(reason)
          phase = helper.dig?("phase").try(&.as_s?)
          why = helper.dig?("reason").try(&.as_s?)
          reason = "#{why}#{phase ? " (#{phase})" : ""}" if why
        rescue JSON::ParseException
        end
      end
      parts << "error #{[code, reason].compact.reject(&.empty?).join(": ")}" if code || reason
    end

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
    url = "#{chaos_charts}/faults/kubernetes/#{fault}/fault.yaml"
    # The local directory first, outside the rescue: a directory that cannot
    # be created is a problem of the machine the suite runs on, not a fault
    # that could not be installed.
    chaos_manifests_path
    experiment_path = begin
      download_template(url, "#{task_name}_experiment.yaml")
    rescue ex : File::Error
      # Writing the template on this machine failed (a directory that is not
      # writable): the machine's problem, so an error, not a skipped fault.
      raise ex
    rescue ex : Exception
      raise FaultInstallError.new(fault, "downloaded from #{url_without_credentials(url)}", ex.message.to_s.lines.first?.to_s.strip)
    end
    begin
      KubectlClient::Apply.file(experiment_path, namespace: namespace)
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      raise FaultInstallError.new(fault, "applied in namespace #{namespace}", apply_error(ex))
    end

    rbac_path = "#{chaos_manifests_path}/#{task_name}_rbac.yaml"
    File.write(rbac_path, LITMUS_RBAC[fault].gsub("namespace: default", "namespace: #{namespace}"))
    begin
      KubectlClient::Apply.file(rbac_path)
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      raise FaultInstallError.new(fault, "given its RBAC in namespace #{namespace}", apply_error(ex))
    end

    experiment_path
  end

  # The line of a failed kubectl apply that names the error, or its first line.
  private def self.apply_error(ex : Exception) : String
    lines = ex.message.to_s.lines.map(&.strip)
    lines.find { |l| l =~ /error/i } || lines.first? || ""
  end

  def self.download_template(url, filename)
    Log.info {"download_template url, filename: #{url_without_credentials(url)}, #{filename}"}
    cmp = chaos_manifests_path()
    filepath = "#{cmp}/#{filename}"
    Log.info {"filepath: #{filepath}"}

    download_file(url, filepath)

    filepath
  end
end
