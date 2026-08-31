# coding: utf-8
require "sam"
require "../utils/utils.cr"

# (rafal-lal) TODO: couple of TODOs found here before refactoring: saving for now
# todo in resilience node_drain task
# todo get node name
# todo download litmus file then modify it with add_node_selector
# todo apply modified litmus file

namespace "setup" do
  desc "Install LitmusChaos"
  task "install_litmus" do |_, args|
    logger = SLOG.for("install_litmus")
    logger.info { "Installing Litmus tool" }
    failed_msg = "Task 'install_litmus' failed"

    begin
      KubectlClient::Apply.namespace(LitmusManager::LITMUS_NAMESPACE)
    rescue KubectlClient::ShellCMD::AlreadyExistsError
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while creating '#{LitmusManager::LITMUS_NAMESPACE}' namespace: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end

    StatusLine.push "Installing the LitmusChaos operator into the cluster..."
    begin
      KubectlClient::Utils.label("namespace", LitmusManager::LITMUS_NAMESPACE,
        ["pod-security.kubernetes.io/enforce=privileged"])
      KubectlClient::Apply.file(LitmusManager::LITMUS_OPERATOR, namespace: LitmusManager::LITMUS_NAMESPACE)
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while installing Litmus tool: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end

    logger.info { "Litmus tool has been installed" }
    StatusLine.pop
  end

  desc "Uninstall LitmusChaos"
  task "uninstall_litmus" do |_, args|
    logger = SLOG.for("uninstall_litmus")
    logger.info { "Uninstalling Litmus tool" }

    begin
      KubectlClient::Delete.resource("chaosengine", extra_opts: "--all --all-namespaces")
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      # Cluster may not have the chaosengine CRD at all (litmus not installed) - not a failure.
      logger.warn { "Could not delete chaosengine resources: #{ex.message}" }
    end

    begin
      KubectlClient::Delete.file(LitmusManager::LITMUS_OPERATOR, namespace: LitmusManager::LITMUS_NAMESPACE)
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while deleting Litmus operator: #{ex.message}" }
      stdout_failure("Task 'uninstall_litmus' failed")
      next
    end

    logger.info { "Litmus tool has been uninstalled" }
  end
end
