require "sam"
require "../../modules/cluster_tools"
require "../utils/utils.cr"
require "../utils/workload_diagnostics.cr"

# Why cluster-tools is not ready, in the cluster's own words; setup and
# cnf_install both stop on it.
def stdout_cluster_tools_not_ready(ex : ClusterTools::NotReadyException)
  lines = WorkloadDiagnostics.problems("DaemonSet", "cluster-tools", ClusterTools.namespace)
  stdout_failure "Error: #{ex.message}"
  lines.each { |line| stdout_failure "  #{line}" }
  stdout_failure "The suite reads the CNF's containers through the cluster-tools DaemonSet (privileged, hostPID) on every node; " +
                 "without it the tests that inspect containers cannot run. The lines above say why the pods are not ready: " +
                 "an admission policy that refuses them (Pod Security, Kyverno, a webhook), an image that cannot be pulled, or a node that cannot schedule them."
end

# The helper is up but cannot inspect containers on some node: the runtime
# it found is unreachable, unsupported, or not the kubelet's. Setup and
# cnf_install both stop on it.
def stdout_cluster_tools_runtime_problems(ex : ClusterTools::RuntimeException)
  stdout_failure "Error: cluster-tools cannot inspect containers on every node:"
  ex.message.to_s.lines.each { |line| stdout_failure "  #{line}" }
  stdout_failure "The suite reads the CNF's containers through the container runtime of each node (containerd or CRI-O), " +
                 "which the cluster-tools pod reaches at the endpoint the kubelet uses. The run stops here: " +
                 "every test that inspects containers would skip on that node otherwise."
end

namespace "setup" do
  desc "Install CNTi Test Suite Cluster Tools"
  task "install_cluster_tools", ["setup:create_namespace"] do |_, args|
    logger = SLOG.for("install_cluster_tools")
    logger.info { "Installing cluster_tools on the cluster" }
    StatusLine.push "Installing cluster-tools on every node (first run pulls the image)..."

    begin
      ClusterTools.install
    rescue ex : ClusterTools::NamespaceDoesNotExistException
      logger.error { "Error while installing: #{ex.message}" }
      stdout_failure "Error: Namespace cnti-testsuite does not exist.\n" +
                     "Please run 'cnti-testsuite setup' to create the necessary namespace."
      exit(1)
    rescue ex : ClusterTools::RuntimeException
      logger.error { "Error while installing: #{ex.message}" }
      stdout_cluster_tools_runtime_problems(ex)
      exit(1)
    rescue ex : ClusterTools::NotReadyException
      # The run stops here: the tests that read the CNF's containers need a
      # pod of this DaemonSet on every node, and a run that went on would
      # skip them without a cause (#2828). The cluster's own explanation (an
      # admission policy refusing the pod, an image that cannot be pulled, a
      # node that cannot schedule it) is in the pods' state and the events.
      logger.error { "Error while installing: #{ex.message}" }
      stdout_cluster_tools_not_ready(ex)
      exit(1)
    rescue ex : Exception
      logger.error { "Error while installing: #{ex.message}" }
      stdout_failure "Unexpected error occured. Check logs for more info."
      exit(1)
    end
    logger.info { "cluster_tools has been installed on the cluster" }
    StatusLine.pop
  end

  desc "Uninstall CNTi Test Suite Cluster Tools"
  task "uninstall_cluster_tools" do |_, args|
    logger = SLOG.for("uninstall_cluster_tools")
    logger.info { "Uninstalling cluster_tools from the cluster" }

    begin
      ClusterTools.uninstall
    rescue ex : ClusterTools::NamespaceDoesNotExistException
      logger.error { "Error while uninstalling: #{ex.message}" }
      stdout_failure "Error: Namespace cnti-testsuite does not exist.\n" +
                     "Please run 'cnti-testsuite setup' to create the necessary namespace."
      exit(1)
    rescue ex : Exception
      logger.error { "Error while installing: #{ex.message}" }
      stdout_failure "Unexpected error occured. Check logs for more info."
      exit(1)
    end
    logger.info { "cluster_tools has been uninstalled on the cluster" }
  end
end
