require "sam"
require "file_utils"
require "http/client"
require "../utils/utils.cr"

namespace "setup" do
  desc "Install Cluster API for Kind"
  task "install_cluster_api" do |_, args|
    logger = SLOG.for("install_cluster_api")
    logger.info { "Installing Cluster API tool" }
    failed_msg = "Task 'install_cluster_api' failed"

    if Dir.exists?(Setup::CLUSTER_API_DIR)
      logger.notice { "cluster api directory: '#{Setup::CLUSTER_API_DIR}' already exists, clusterctl should be available" }
      next
    end

    FileUtils.mkdir_p(Setup::CLUSTER_API_DIR)
    begin
      download(Setup::CLUSTER_API_URL, Setup::CLUSTERCTL_BINARY)
    rescue ex : Exception
      logger.error { "Error while downloading clusterctl binary" }
      stdout_error(failed_msg)
      # (rafal-lal) TODO: SAM tasks error handling in setup, should we fail whole testsuite run / ignore
      # or something else? Applicable to all Setup tasks.
      next
    end
    logger.debug { "Downloaded clusterctl binary" }

    resp = ShellCmd.run("chmod +x #{Setup::CLUSTERCTL_BINARY}")
    unless resp[:status].success?
      logger.error { "Error while making cluster api binary: '#{Setup::CLUSTERCTL_BINARY}' executable" }
      stdout_error(failed_msg)
      next
    end

    File.write("#{Setup::CLUSTER_API_DIR}/clusterctl.yaml", "CLUSTER_TOPOLOGY: \"true\"")
    unless ShellCmd.run("#{Setup::CLUSTERCTL_BINARY} init --infrastructure docker")[:status].success?
      logger.error { "Error while initializing Cluster API on the cluster" }
      stdout_error(failed_msg)
    end

    cluster_name = "capi-quickstart"
    cluster_tpl_file = "#{Setup::CLUSTER_API_DIR}/capi.yaml"
    # (rafal-lal) TODO: add kubernetes version const to use widely in codebase
    generate_cmd = "#{Setup::CLUSTERCTL_BINARY} generate cluster #{cluster_name}" +
                   "--kubernetes-version v1.32.0" +
                   "--control-plane-machine-count=1" +
                   "--worker-machine-count=1" +
                   "--flavor development" +
                   "--target-namespace #{DEFAULT_CNF_NAMESPACE}" +
                   "> #{cluster_tpl_file}"
    unless ShellCmd.run(generate_cmd)[:status].success?
      logger.error { "Error while generating workload cluster YAML template" }
      stdout_error(failed_msg)
    end

    is_ready = false
    begin
      KubectlClient::Apply.file(cluster_tpl_file)
      is_ready = KubectlClient::Wait.wait_for_resource_key_value("cluster", cluster_name,
        {"status", "phase"}, "Provisioned", 300, DEFAULT_CNF_NAMESPACE)
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while waiting for cluster to be Ready: #{ex.message}" }
      stdout_error(failed_msg)
    end

    unless is_ready
      logger.error { "Manifest apply not succesful or timed out while waiting for cluster to be Ready" }
      stdout_error(failed_msg)
      next
    end

    logger.info { "Cluster API provisioned cluster '#{cluster_name}' is ready to use" }
  end

  desc "Uninstall Cluster API"
  task "uninstall_cluster_api" do |_, args|
    logger = SLOG.for("uninstall_cluster_api")
    logger.info { "Uninstalling Cluster API tool" }

    begin
      KubectlClient::Delete.file("#{Setup::CLUSTER_API_DIR}/capi.yaml")
    rescue KubectlClient::ShellCMD::NotFoundError
      logger.debug { "Cluster API 'cluster' resource does not exists" }
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while deleting Cluster API 'cluster' resource: #{ex.message}" }
      stdout_error("Error while deleting Cluster API 'cluster' resource. Check logs for more info.")
    end

    response = ShellCmd.run("#{Setup::CLUSTERCTL_BINARY} delete --all --include-crd --include-namespace")
    unless response[:status].success?
      logger.error { "Error while deleting Cluster API from the cluster: #{response[:error]}" }
      stdout_error("Error while deleting Cluster API 'cluster' resource. Check logs for more info.")
      next
    end

    logger.info { "Cluster API uninstalled from the cluster" }
  end
end
