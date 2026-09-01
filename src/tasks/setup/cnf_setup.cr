require "sam"
require "../utils/utils.cr"

desc "Install the CNF under test from a cnti-testsuite.yaml config"
task "cnf_install", ["setup:install_local_helm", "setup:create_namespace"] do |_, args|
  logger = SLOG.for("cnf_install")
  logger.info { "Installing CNF to cluster" }

  # A wrong command line is a usage error; find out before ClusterTools is
  # deployed, not after.
  CNFInstall.parse_install_cli_args(args)

  if CNFManager.cnf_installed?
    stdout_failure "A CNF is already installed. Installation of multiple CNFs is not allowed."
    stdout_failure "To install a new CNF, uninstall the existing one by running: cnf_uninstall"
    exit 1
  end

  StatusLine.push "CNF installation in progress..."
  StatusLine.push "Installing cluster-tools on every node (first run pulls the image)..."
  if ClusterTools.install
    StatusLine.pop
  else
    stdout_failure "The ClusterTools installation timed out. Please check the status of the cluster-tools pods."
    exit 1
  end

  CNFInstall.install_cnf(args)
  logger.info { "CNF installed successfuly" }
  StatusLine.pop
  stdout_success "CNF installation complete."
end

desc "Uninstall the CNF under test and remove its installed files"
task "cnf_uninstall" do |_, args|
  logger = SLOG.for("cnf_uninstall")
  logger.info { "Uninstalling CNF from cluster" }

  StatusLine.push "CNF uninstallation in progress..."
  result = CNFInstall.uninstall_cnf(args)
  StatusLine.pop

  if result
    stdout_success "CNF uninstallation succeeded."
  else
    stdout_failure "CNF uninstallation failed."
    exit(1)
  end
end

desc "Check a cnti-testsuite.yaml for errors without installing anything"
task "validate_config" do |_, args|
  if args.named["cnf-config"]?
    config_path = CNFInstall.ensure_cnf_config_path_file(args.named["cnf-config"].to_s)
    config = CNFInstall::Config.parse_cnf_config_from_file(config_path)
    stdout_success "Successfully validated CNF config"
    SLOG.for("validate_config").debug { "Config: #{config.inspect}" }
  else
    usage_error! "Usage: validate_config --cnf-config PATH"
  end
end
