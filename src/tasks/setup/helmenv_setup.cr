require "sam"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Helm"
  task "install_local_helm" do |_, args|
    logger = SLOG.for("install_local_helm")
    logger.info { "Installing Helm tool" }

    if !Helm::Binary.get.empty? && !ENV.has_key?("force_install")
      logger.notice { "Helm installation has been found on the system, skipping" }
      next
    end

    unless Helm.install_local_helm
      stdout_failure("Task 'install_local_helm' failed")
      exit(1)
    end

    stdout_success("Helm tool has been installed")
  end

  desc "Cleans up Helm"
  task "uninstall_local_helm" do |_, args|
    SLOG.for("uninstall_local_helm").info { "Uninstalling Helm tool" }
    Helm.uninstall_local_helm
  end
end
