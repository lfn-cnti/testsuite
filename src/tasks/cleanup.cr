require "sam"
require "file_utils"
require "colorize"
require "totem"

desc "Alias for cnf_uninstall"
task "uninstall", ["cnf_uninstall"] do |_, args|
end

# Private task
task "_tools_uninstall_start" do
  stdout_success "Uninstalling testsuite helper tools."
end

desc "Cleans up the CNF Test Suite helper tools and containers"
task "tools_uninstall", [
  "_tools_uninstall_start",
  "setup:uninstall_sonobuoy",
  "setup:uninstall_litmus",
  "setup:uninstall_kubescape",
  "setup:uninstall_cluster_tools",
  "setup:uninstall_opa",
  "setup:uninstall_kyverno",
  "setup:uninstall_jaeger",
  "setup:uninstall_fluentd",
  "setup:uninstall_fluentdbitnami",
  "setup:uninstall_fluentbit",
  "setup:cluster_api_uninstall",
  "uninstall_ueransim",
  "uninstall_kind",
  # Helm needs to be uninstalled last to allow other uninstalls to use helm if necessary.
  # Check this issue for details - https://github.com/cncf/cnf-testsuite/issues/1586
  "setup:uninstall_local_helm",
] do |_, args|
  # (rafal-lal) Temporary solution that will be replaced soon
  Dockerd.uninstall
  FileUtils.rm_rf("#{tools_path}/dockerd-manifest.yml")
  FileUtils.rm_rf("#{tools_path}/docker-config-manifest.yml")
  stdout_success "Testsuite helper tools uninstalled."
end

desc "Cleans up the CNF Test Suite sample projects, helper tools, and containers"
task "uninstall_all", ["cnf_uninstall", "tools_uninstall"] do |_, args|
end

desc "Deletes all results files from the results directory"
task "delete_results" do |_, args|
  files = Dir.glob(File.join(CNFManager::Points::Results.dir, "cnf-testsuite-results-*.yml"))
  files.each { |f| File.delete(f) }
  File.delete?(CNFManager::Points::Results.latest)
  Log.info { "Deleted #{files.size} results file(s)" }
  stdout_success "Deleted #{files.size} results file(s)."
end
