require "sam"
require "file_utils"
require "colorize"
require "../modules/cluster_tools"
require "totem"
require "./utils/utils.cr"

# CHAOS_MESH_VERSION = "v0.8.0"

desc "Install CNF Test Suite Cluster Tools"
task "install_cluster_tools" do |_, args|
  begin
    ClusterTools.install
  rescue e : ClusterTools::NamespaceDoesNotExistException 
    Log.error { "#{e.message}" }
    stdout_failure "Error: Namespace cnf-testsuite does not exist.\nPlease run 'cnf-testsuite setup' to create the necessary namespace."
    exit(1)
  end
end

desc "Uninstall CNF Test Suite Cluster Tools"
task "uninstall_cluster_tools" do |_, args|
  begin
    ClusterTools.uninstall
  rescue e : ClusterTools::NamespaceDoesNotExistException
    Log.error { "#{e.message}" }
    stdout_failure "Error: Namespace cnf-testsuite does not exist.\nPlease run 'cnf-testsuite setup' to create the necessary namespace."
    exit(1)
  end
end
