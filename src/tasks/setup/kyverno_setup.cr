require "sam"
require "../utils/utils.cr"

namespace "setup" do
  desc "Install Kyverno"
  task "install_kyverno" do |_, args|
    logger = SLOG.for("install_kyverno")
    logger.info { "Installing Kyverno tool" }

    unless Kyverno.install
      logger.error { "Error while installing Kyverno tool" }
      stdout_failure("Task 'install_kyverno' failed")
      exit(1)
    end

    logger.info { "Kyverno tool has been installed" }
  end

  desc "Uninstall Kyverno"
  task "uninstall_kyverno" do |_, args|
    logger = SLOG.for("uninstall_kyverno")
    logger.info { "Uninstalling Kyverno tool" }

    unless Kyverno.uninstall
      logger.error { "Error while uninstalling Kyverno tool" }
      stdout_failure("Task 'uninstall_kyverno' failed")
      exit(1)
    end

    logger.info { "Kyverno tool has been uninstalled" }
  end
end
