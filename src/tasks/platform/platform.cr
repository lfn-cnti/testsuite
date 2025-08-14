# coding: utf-8
desc "Platform Tests"
task "platform", ["setup:install_local_helm", "k8s_conformance", "platform:observability", "platform:resilience", "platform:hardware_and_scheduling", "platform:security"]  do |_, args|
  Log.debug { "platform" }

  total = CNFManager::Points.total_points("platform")
  if total > 0
    stdout_success "Final platform score: #{total} of #{CNFManager::Points.total_max_points("platform")}"
  else
    stdout_failure "Final platform score: #{total} of #{CNFManager::Points.total_max_points("platform")}"
  end

  if CNFManager::Points.failed_required_tasks.size > 0
    stdout_failure "Test Suite failed!"
    stdout_failure "Failed required tasks: #{CNFManager::Points.failed_required_tasks.inspect}"
    update_yml("#{CNFManager::Points::Results.file}", "exit_code", "1")
  end
  stdout_info "Test results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
end

desc "Does the platform pass the K8s conformance tests?"
task "k8s_conformance" do |t, args|
  CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do
    current_dir = FileUtils.pwd
    stdout_warning "k8s_conformance: starting in #{current_dir}"
    sonobuoy = "#{tools_path}/sonobuoy/sonobuoy"

    # --- Clean up old results
    delete_cmd = "#{sonobuoy} delete --all --wait"
    stdout_warning "delete_cmd: #{delete_cmd.inspect}"
    delete_stdout = IO::Memory.new
    delete_stderr = IO::Memory.new
    delete_status = Process.run(
      delete_cmd,
      shell:  true,
      output: delete_stdout,
      error:  delete_stderr
    )
    stdout_warning "delete: success?=#{delete_status.success?} stdout.bytes=#{delete_stdout.to_s.bytesize} stderr.bytes=#{delete_stderr.to_s.bytesize}"
    unless delete_stderr.to_s.empty?
      stderr_preview = delete_stderr.to_s.lines.first(10).join("\n")
      stdout_warning "delete stderr preview:\n#{stderr_preview}"
    end

    # --- Run the tests
    testrun_stdout = IO::Memory.new
    testrun_stderr = IO::Memory.new
    env = ENV["CRYSTAL_ENV"]?
    stdout_warning "CRYSTAL_ENV=#{env.inspect}"

    if env == "TEST"
      cmd = "#{sonobuoy} run --wait --mode quick"
      stdout_warning "run_cmd(quick): #{cmd.inspect}"
    else
      cmd = "#{sonobuoy} run --wait"
      stdout_warning "run_cmd(conformance): #{cmd.inspect}"
    end

    t0 = Time.utc
    testrun_status = Process.run(
      cmd,
      shell:  true,
      output: testrun_stdout,
      error:  testrun_stderr
    )
    dt = (Time.utc - t0)
    stdout_warning "run: success?=#{testrun_status.success?} elapsed=#{dt} stdout.bytes=#{testrun_stdout.to_s.bytesize} stderr.bytes=#{testrun_stderr.to_s.bytesize}"
    unless testrun_stderr.to_s.empty?
      preview = testrun_stderr.to_s.lines.first(10).join("\n")
      stdout_warning "run stderr preview:\n#{preview}"
    end

    # --- Retrieve results + print report
    cmd = "results=$(#{sonobuoy} retrieve); #{sonobuoy} results $results"
    stdout_warning "retrieve+results cmd: #{cmd.inspect}"
    results_stdout = IO::Memory.new
    results_status = Process.run(cmd, shell: true, output: results_stdout, error: results_stdout)
    results = results_stdout.to_s
    stdout_warning "results: success?=#{results_status.success?} bytes=#{results.bytesize}"

    # Results head/tail previews (trim output volume)
    lines = results.lines
    head  = lines.first(15).join("\n")
    tail  = lines.last(10).join("\n")
    stdout_warning "results HEAD(15):\n#{head}"
    stdout_warning "results TAIL(10):\n#{tail}"
    stdout_warning "results contains 'Failed:'? -> #{results.includes?("Failed:")}"

    # --- Parse the Failed count (robust; no exception on bad/missing)
    failed_count = nil
    if failed_match_data = results.match(/Failed:\s+(\S+)/)
      failed_raw_value = failed_match_data[1]
      stdout_warning "regex matched. raw Failed value=#{failed_raw_value.inspect}"
      if failed_integer = failed_raw_value.to_i?
        stdout_warning "parsed Failed integer=#{failed_integer}"
        failed_count = failed_integer
      else
        stdout_warning "to_i? returned nil for Failed value=#{failed_raw_value.inspect}"
        stdout_warning "RAW RESULTS (full) begin\n#{results}\nRAW RESULTS end"
      end
    else
      stdout_warning "no 'Failed:' line matched in results"
      stdout_warning "RAW RESULTS (full) begin\n#{results}\nRAW RESULTS end"
    end

    # --- Decide result
    if failed_count.nil?
      stdout_warning "decision: ERROR (unable to determine failures)"
      CNFManager::TestCaseResult.new(
        CNFManager::ResultStatus::Error,
        "Unable to determine failure count from Sonobuoy results"
      )
    elsif failed_count > 0
      stdout_warning "decision: FAILED (#{failed_count} > 0)"
      CNFManager::TestCaseResult.new(
        CNFManager::ResultStatus::Failed,
        "K8s conformance test has #{failed_count} failure(s)!"
      )
    else
      stdout_warning "decision: PASSED (0 failures)"
      CNFManager::TestCaseResult.new(
        CNFManager::ResultStatus::Passed,
        "K8s conformance test has no failures"
      )
    end
  rescue ex
    stdout_warning "EXCEPTION: #{ex.message}"
    ex.backtrace.each { |x| stdout_warning x }
    CNFManager::TestCaseResult.new(
      CNFManager::ResultStatus::Error,
      "Exception while running Sonobuoy: #{ex.message}"
    )
  ensure
    FileUtils.rm_rf(Dir.glob("*sonobuoy*.tar.gz"))
    stdout_warning "k8s_conformance: cleanup complete"
  end
end

desc "Is Cluster Api available and managing a cluster?"
task "clusterapi_enabled" do |t, args|
  CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do
    unless check_poc(args)
      next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Cluster API not in poc mode")
    end

    Log.debug { "clusterapi_enabled" }
    Log.info { "clusterapi_enabled args #{args.inspect}" }

    # We test that the namespaces for cluster resources exist by looking for labels
    # I found those by running
    # clusterctl init
    # kubectl -n capi-system describe deployments.apps capi-controller-manager
    # https://cluster-api.sigs.k8s.io/clusterctl/commands/init.html#additional-information

    # this indicates that cluster-api is installed
    clusterapi_namespaces_json = KubectlClient::Get.resource("namespace", selector: "clusterctl.cluster.x-k8s.io")
    Log.info { "clusterapi_namespaces_json: #{clusterapi_namespaces_json}" }

    # check that a node is actually being manageed
    # TODO: suppress msg in the case that this resource does-not-exist which is what happens when cluster-api is not installed
    cmd = "kubectl get kubeadmcontrolplanes.controlplane.cluster.x-k8s.io -o json"
    Process.run(
      cmd,
      shell: true,
      output: clusterapi_control_planes_output = IO::Memory.new,
      error: stderr = IO::Memory.new
    )

    proc_clusterapi_control_planes_json = -> do
      begin
        JSON.parse(clusterapi_control_planes_output.to_s)
      rescue JSON::ParseException
        # resource does-not-exist rescue to empty json
        JSON.parse("{}")
      end
    end

    clusterapi_control_planes_json = proc_clusterapi_control_planes_json.call
    Log.info { "clusterapi_control_planes_json: #{clusterapi_control_planes_json}" }

    if clusterapi_namespaces_json["items"]? && clusterapi_namespaces_json["items"].as_a.size > 0 && clusterapi_control_planes_json["items"]? && clusterapi_control_planes_json["items"].as_a.size > 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Cluster API is enabled")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Cluster API NOT enabled")
    end
  end
end
