require "sam"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up OPA in the K8s Cluster"
  task "install_opa", ["helm_local_install", "create_namespace"] do |_, args|
    logger = SLOG.for("install_opa")
    logger.info { "Installing Open Policy Agent tool" }
    failed_msg = "Task 'install_opa' failed"

    helm_install_args_list = [
      "--set auditInterval=1",
      "--set postInstall.labelNamespace.enabled=false",
      "-n #{TESTSUITE_NAMESPACE}",
    ]
    helm_install_args_list.push("--set psp.enabled=false") if !version_less_than(KubectlClient.server_version, "1.25.0")
    helm_install_args = helm_install_args_list.join(" ")

    begin
      Helm.helm_repo_add("gatekeeper", GATEKEEPER_REPO)
    rescue ex : Helm::ShellCMD::HelmCMDException
      logger.error { "Error while installing OPA Gatekeeper: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end

    begin
      # (rafal-lal) TODO: should we ensure the release names to be specific to testsuite, imagine sitation in which user already
      # has gatekeepr installed, will that be a problem?
      Helm.install("opa-gatekeeper", "gatekeeper/gatekeeper", values: helm_install_args)
    rescue e : Helm::CannotReuseReleaseNameError
      logger.notice { "OPA Gatekeeper already installed on the cluster" }
    rescue ex : Helm::ShellCMD::HelmCMDException
      logger.error { "Error while installing OPA Gatekeeper: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end
    logger.debug { "OPA Gatekeeper chart applied" }

    begin
      KubectlClient::Wait.wait_for_install_by_apply("./embedded_files/constraint_template.yml")
      KubectlClient::Wait.wait_for_condition("crd", "requiretags.constraints.gatekeeper.sh", "condition=established", 300)
      KubectlClient::Apply.file("./embedded_files/enforce-image-tag.yml")
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while installing OPA Gatekeeper: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end

    logger.info { "OPA Gatekeeper tool has been installed" }
  end

  desc "Uninstall OPA"
  task "uninstall_opa" do |_, args|
    logger = SLOG.for("uninstall_opa")
    logger.info { "Uninstalling Open Policy Agent tool" }
    failed_msg = "Task 'uninstall_opa' failed"

    begin
      Helm.uninstall("opa-gatekeeper", TESTSUITE_NAMESPACE)
    rescue Helm::ShellCMD::ReleaseNotFound
    rescue ex : Helm::ShellCMD::HelmCMDException
      logger.error { "Error while uninstalling OPA Gatekeeper: #{ex.message}" }
      stdout_failure(failed_msg)
    end

    begin
      KubectlClient::Delete.file("./embedded_files/enforce-image-tag.yml")
    rescue KubectlClient::ShellCMD::NotFoundError
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while uninstalling OPA Gatekeeper: #{ex.message}" }
      stdout_failure(failed_msg)
    end

    begin
      KubectlClient::Delete.file("./embedded_files/constraint_template.yml")
    rescue KubectlClient::ShellCMD::NotFoundError
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Error while uninstalling OPA Gatekeeper: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end

    logger.info { "Open Policy Agent tool has been uninstalled" }
  end
end
