require "sam"
require "cluster_tools"

namespace "setup" do
  desc "Install CNF Test Suite Cluster Tools"
  task "install_cluster_tools" do |_, args|
    logger = SLOG.for("install_cluster_tools")
    logger.info { "Installing cluster_tools on the cluster" }

    begin
      ClusterTools.install
    rescue ex : ClusterTools::NamespaceDoesNotExistException
      logger.error { "Error while installing: #{ex.message}" }
      stdout_failure "Error: Namespace cnf-testsuite does not exist.\n" +
                     "Please run 'cnf-testsuite setup' to create the necessary namespace."
      exit(1)
    rescue ex : Exception
      logger.error { "Error while installing: #{ex.message}" }
      stdout_failure "Unexpected error occured. Check logs for more info."
      exit(1)
    end
    logger.info { "cluster_tools has been installed on the cluster" }
  end

  desc "Uninstall CNF Test Suite Cluster Tools"
  task "uninstall_cluster_tools" do |_, args|
    logger = SLOG.for("uninstall_cluster_tools")
    logger.info { "Uninstalling cluster_tools from the cluster" }

    begin
      ClusterTools.uninstall
    rescue e : ClusterTools::NamespaceDoesNotExistException
      logger.error { "Error while uninstalling: #{ex.message}" }
      stdout_failure "Error: Namespace cnf-testsuite does not exist.\n" +
                     "Please run 'cnf-testsuite setup' to create the necessary namespace."
      exit(1)
    rescue ex : Exception
      logger.error { "Error while installing: #{ex.message}" }
      stdout_failure "Unexpected error occured. Check logs for more info."
      exit(1)
    end
    logger.info { "cluster_tools has been uninstalled on the cluster" }
  end
end
