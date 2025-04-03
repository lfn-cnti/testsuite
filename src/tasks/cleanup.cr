require "sam"
require "file_utils"
require "colorize"
require "totem"

desc "Alias for cnf_uninstall"
task "uninstall", ["cnf_uninstall"] do  |_, args|
end

# Private task
task "_tools_uninstall_start" do
  stdout_success "Uninstalling testsuite helper tools."
end

desc "Cleans up the CNF Test Suite helper tools and containers"
task "tools_uninstall", [
    "_tools_uninstall_start",
    "setup:uninstall_sonobuoy",
    "setup:uninstall_chaosmesh",
    "setup:uninstall_litmus",
    "setup:uninstall_dockerd",
    "setup:uninstall_kubescape",
    "setup:uninstall_cluster_tools",
    "setup:uninstall_opa",
 
    # Helm needs to be uninstalled last to allow other uninstalls to use helm if necessary.
    # Check this issue for details - https://github.com/cncf/cnf-testsuite/issues/1586
    "uninstall_local_helm"
  ] do |_, args|
  stdout_success "Testsuite helper tools uninstalled."
end

desc "Cleans up the CNF Test Suite sample projects, helper tools, and containers"
task "uninstall_all", ["cnf_uninstall", "tools_uninstall"] do |_, args|
end

task "delete_results" do |_, args|
  if CNFManager::Points::Results.file_exists?
    File.delete(CNFManager::Points::Results.file)
    Log.debug { "Deleted results file at #{CNFManager::Points::Results.file}" }
  end
end
