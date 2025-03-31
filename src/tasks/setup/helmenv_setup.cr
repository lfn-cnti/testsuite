require "sam"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Helm"
  task "install_local_helm" do |_, args|
    logger = SLOG.for("install_local_helm")
    logger.info { "Installing Helm tool" }
    failed_msg = "Task 'install_local_helm' failed"

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
  task "uninstall_local_helm" do |_, args|
    SLOG.for("uninstall_local_helm").info { "Uninstalling Helm tool" }
    Helm.uninstall_local_helm
  end
end
