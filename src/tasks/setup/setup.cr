require "sam"

desc "Sets up the CNF test suite, the K8s cluster, and upstream projects"
task "setup", ["version", "setup:cnf_directory_setup", "setup:helm_local_install", "prereqs",
               "setup:create_namespace", "setup:configuration_file_setup", "setup:install_apisnoop",
               "setup:install_sonobuoy", , "setup:install_kind"] do |_, args|
  stdout_success "Dependency installation complete"
end

namespace "setup" do
  task "create_namespace" do |_, args|
    logger = SLOG.for("create_namespace")
    logger.info { "Creating namespace for CNTI testsuite" }

    ensure_kubeconfig!
    begin
      KubectlClient::Apply.namespace(TESTSUITE_NAMESPACE)
      stdout_success "Created #{TESTSUITE_NAMESPACE} namespace on the Kubernetes cluster"
      logger.info { "#{TESTSUITE_NAMESPACE} namespace created" }
    rescue ex : KubectlClient::ShellCMD::AlreadyExistsError
      stdout_success "#{TESTSUITE_NAMESPACE} namespace already exists on the Kubernetes cluster"
      logger.info { "#{TESTSUITE_NAMESPACE} namespace already exists, not creating" }
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      stdout_failure "Could not create #{TESTSUITE_NAMESPACE} namespace on the Kubernetes cluster"
      logger.error { "Failed to create #{TESTSUITE_NAMESPACE} namespace: #{ex.message}" }
      exit(1)
    end

    begin
      KubectlClient::Utils.label("namespace", TESTSUITE_NAMESPACE, ["pod-security.kubernetes.io/enforce=privileged"])
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Failed to label #{TESTSUITE_NAMESPACE} namespace: #{ex.message}" }
      # (rafal-lal) TODO: should testsuite exit here?
    end
  end

  desc "Sets up initial directories for the cnf-testsuite"
  task "cnf_directory_setup" do |_, args|
    logger = SLOG.for("cnf_directory_setup")
    logger.info { "Creating directories for CNTI testsuite" }

    begin
      FileUtils.mkdir_p(CNF_DIR)
      FileUtils.mkdir_p("tools")
    rescue ex : Exception
      logger.error { "Error while creating directories for testsuite: #{ex.message}" }
      stdout_failure "Task 'cnf_directory_setup' failed. Check logs for more info."
      exit 1
    end
    stdout_success "Successfully created directories for cnf-testsuite"
  end

  task "configuration_file_setup" do |_, args|
    logger = SLOG.for("configuration_file_setup").info { "Creating configuration file" }
    CNFManager::Points.create_points_yml
  end
end
