require "sam"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Helm"
  task "helm_local_install" do |_, args|
    logger = SLOG.for("helm_local_install")
    logger.info { "Installing Helm tool" }
    failed_msg = "Task 'helm_local_install' failed"

    if !Helm::Binary.get.empty? && !ENV.has_key?("force_install")
      logger.notice { "Helm installation has been found on the system, skipping." }
      next
    end

    unless Helm.install_local_helm
      stdout_failure(failed_msg)
      exit(1)
    end

    logger.info { "Helm tool has been installed" }
  end

  desc "Cleans up Helm"
  task "helm_local_uninstall" do |_, args|
    SLOG.for("helm_local_uninstall").info { "Uninstalling Helm tool" }
    Helm.uninstall_local_helm
  end
end
