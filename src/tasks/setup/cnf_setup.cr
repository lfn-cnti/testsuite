require "sam"
require "../utils/utils.cr"

namespace "setup" do
  task "cnf_install", ["helm_local_install", "create_namespace"] do |_, args|
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
    stdout_success "CNF installation ended."
  end

  task "cnf_uninstall" do |_, args|
    logger = SLOG.for("cnf_uninstall")
    logger.info { "Uninstalling CNF from cluster" }
    CNFInstall.uninstall_cnf
    logger.info { "CNF uninstallation ended" }
  end
end
