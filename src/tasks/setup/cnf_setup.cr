require "sam"
require "../utils/utils.cr"

task "cnf_install", ["setup:helm_local_install", "setup:create_namespace"] do |_, args|
  logger = SLOG.for("cnf_install")
  logger.info { "Installing CNF to cluster" }

  if CNFManager.cnf_installed?
    stdout_warning "A CNF is already installed. Installation of multiple CNFs is not allowed."
    stdout_warning "To install a new CNF, uninstall the existing one by running: cnf_uninstall"
    exit 0
  end

  if ClusterTools.install
    stdout_success "ClusterTools installed"
  else
    stdout_failure "The ClusterTools installation timed out. Please check the status of the cluster-tools pods."
    exit 1
  end

  stdout_success "CNF installation start."
  CNFInstall.install_cnf(args)
  logger.info { "CNF installed successfuly" }
  stdout_success "CNF installation complete."
end

task "cnf_uninstall" do |_, args|
  logger = SLOG.for("cnf_uninstall")
  logger.info { "Uninstalling CNF from cluster" }
  CNFInstall.uninstall_cnf
  logger.info { "CNF uninstallation ended" }
end

task "validate_config" do |_, args|
  if args.named["cnf-config"]?
    config = CNFInstall::Config.parse_cnf_config_from_file(args.named["cnf-config"].to_s)
    stdout_success "Successfully validated CNF config"
    SLOG.for("validate_config").info { "Config: #{config.inspect}" }
  else
    stdout_failure "cnf-config parameter needed"
    exit 1
  end
end
