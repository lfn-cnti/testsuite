# coding: utf-8
desc "Platform Tests"
task "platform", ["setup:helm_local_install", "k8s_conformance", "platform:observability", "platform:resilience", "platform:hardware_and_scheduling", "platform:security"]  do |_, args|
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
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "K8s conformance test has #{failed_count} failure(s)!")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "K8s conformance test has no failures")
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

desc "Is Cluster managed by Cluster API"
task "cluster_api_enabled" do |t, args|
  logger = PLOG.for("cluster_api_enabled")
  logger.info { "Testing if cluster has nodes managed by Cluster API" }

  CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do
    # (rafal-lal) TODO: should this still be POC after discussing task
    unless check_poc(args)
      next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Cluster API not in POC mode")
    end

    begin
      nodes = KubectlClient::Get.resource("nodes").dig("items").as_a
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while getting cluster nodes: #{ex.message}" }
      next
    end

    # Check if any of the cluster nodes have Cluster API annotations
    capi_nodes = [] of String
    capi_annotation_found = nodes.any? do |node|
      annotations = node.dig?("metadata", "annotations")
      if annotations.nil?
        false
      else
        if !annotations.dig?("cluster.x-k8s.io/owner-name").nil? &&
           !annotations.dig?("cluster.x-k8s.io/machine").nil? &&
           !annotations.dig?("cluster.x-k8s.io/cluster-name").nil?
          capi_nodes << node.dig("metadata", "name").as_s
          true
        end
      end
    end
    logger.info { "#{capi_nodes.size} out of #{nodes.size} are managed by Cluster API" }

    if capi_annotation_found
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed,
        "At least one node in the cluster is managed by Cluster API")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed,
        "No nodes in the cluster are managed by Cluster API")
    end
  end
end
