require "sam"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Helm"
  task "helm_local_install" do |_, args|
    logger = SLOG.for("helm_local_install")
    logger.info { "Installing Helm tool" }
    failed_msg = "Task 'helm_local_install' failed"

    # Check if proper version of Helm is installed
    if Helm::SystemInfo.global_helm_installed? && !ENV.has_key?("force_install")
      logger.info { "Globally installed helm satisfies required version. Skipping local helm install." }
      next
    end

    unless install_local_helm
      logger.error { "Error while installing Helm tool" }
      stdout_failure(failed_msg)
      next
    end

    logger.info { "Helm tool has been installed" }
  end

  desc "Cleans up Helm"
  task "helm_local_uninstall" do |_, args|
    SLOG.for("helm_local_uninstall").info { "Uninstalling Helm tool" }
    helm_local_cleanup
  end
end
