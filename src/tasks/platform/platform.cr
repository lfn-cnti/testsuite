# coding: utf-8
desc "Platform Tests"
task "platform", ["helm_local_install", "k8s_conformance", "platform:observability", "platform:resilience", "platform:hardware_and_scheduling", "platform:security"]  do |_, args|
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
    Log.for(t.name).debug { "current dir: #{current_dir}" }
    sonobuoy = "#{tools_path}/sonobuoy/sonobuoy"

    # Clean up old results
    delete_cmd = "#{sonobuoy} delete --all --wait"
    Process.run(
      delete_cmd,
      shell: true,
      output: delete_stdout = IO::Memory.new,
      error: delete_stderr = IO::Memory.new
    )
    Log.for(t.name).debug { "sonobuoy delete output: #{delete_stdout}" }

    # Run the tests
    testrun_stdout = IO::Memory.new
    Log.debug { "CRYSTAL_ENV: #{ENV["CRYSTAL_ENV"]?}" }
    if ENV["CRYSTAL_ENV"]? == "TEST"
      Log.info { "Running Sonobuoy using Quick Mode" }
      cmd = "#{sonobuoy} run --wait --mode quick"
      Process.run(
        cmd,
        shell: true,
        output: testrun_stdout,
        error: testrun_stderr = IO::Memory.new
      )
    else
      Log.info { "Running Sonobuoy Conformance" }
      cmd = "#{sonobuoy} run --wait"
      Process.run(
        cmd,
        shell: true,
        output: testrun_stdout,
        error: testrun_stderr = IO::Memory.new
      )
    end
    Log.debug { testrun_stdout.to_s }

    cmd = "results=$(#{sonobuoy} retrieve); #{sonobuoy} results $results"
    results_stdout = IO::Memory.new
    Process.run(cmd, shell: true, output: results_stdout, error: results_stdout)
    results = results_stdout.to_s
    Log.debug { results }

    # Grab the failed line from the results

    failed_count = ((results.match(/Failed: (.*)/)).try &.[1]) 
    if failed_count.to_s.to_i > 0
      CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "K8s conformance test has #{failed_count} failure(s)!")
    else
      CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Passed, "K8s conformance test has no failures")
    end
  rescue ex
    Log.error { ex.message }
    ex.backtrace.each do |x|
      Log.error { x }
    end
  ensure
    FileUtils.rm_rf(Dir.glob("*sonobuoy*.tar.gz"))
  end
end

desc "Is Cluster Api available and managing a cluster?"
task "clusterapi_enabled" do |t, args|
  CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do
    unless check_poc(args)
      next CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Skipped, "Cluster API not in poc mode")
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
      CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Passed, "Cluster API is enabled")
    else
      CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "Cluster API NOT enabled")
    end
  end
end
