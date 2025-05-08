require "sam"

namespace "setup" do
  desc "Install FluentD"
  task "install_fluentd" do |_, args|
    SLOG.for("install_fluentd").info { "Installing FluentD chart" }
    # (rafal-lal) TODO: make sure this external calls are error-handled, logged properly.
    FluentManager::FluentD.new.install
  end

  desc "Uninstall FluentD"
  task "uninstall_fluentd" do |_, args|
    SLOG.for("uninstall_fluentd").info { "Uninstalling FluentD chart" }
    FluentManager::FluentD.new.uninstall
  end

  desc "Install FluentDBitnami"
  task "install_fluentdbitnami" do |_, args|
    SLOG.for("install_fluentdbitnami").info { "Installing Fluentd Bitnami chart" }
    FluentManager::FluentDBitnami.new.install
  end

  desc "Uninstall FluentDBitnami"
  task "uninstall_fluentdbitnami" do |_, args|
    SLOG.for("uninstall_fluentdbitnami").info { "Uninstalling Fluentd Bitnami chart" }
    FluentManager::FluentDBitnami.new.uninstall
  end

  desc "Install FluentBit"
  task "install_fluentbit" do |_, args|
    SLOG.for("install_fluentbit").info { "Installing Fluentbit chart" }
    FluentManager::FluentBit.new.install
  end

  desc "Uninstall FluentBit"
  task "uninstall_fluentbit" do |_, args|
    SLOG.for("uninstall_fluentbit").info { "Uninstalling Fluentbit chart" }
    FluentManager::FluentBit.new.uninstall
  end
end
