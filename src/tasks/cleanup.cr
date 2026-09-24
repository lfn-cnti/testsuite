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

# Removes what the suite deployed into the cluster. The tools it downloaded
# for itself (kubescape and its framework, the kyverno CLI and policies, helm,
# the chaos experiments) stay under the suite home: they carry a version
# marker and are only downloaded again when a pin changes, so removing them
# on every uninstall cost a full re-download per run (and, in CI, a fresh
# exposure to every GitHub outage). tools_purge removes them on request.
desc "Removes the helper tools the suite deployed into the cluster; keeps its local downloads (see tools_purge)"
task "tools_uninstall", [
  "_tools_uninstall_start",
  "setup:uninstall_litmus",
  "setup:uninstall_cluster_tools",
  "setup:uninstall_kyverno",
  "setup:uninstall_jaeger",
  "setup:uninstall_fluentd",
  "setup:uninstall_fluentbit",
] do |_, args|
  # (rafal-lal) Temporary solution that will be replaced soon
  Dockerd.uninstall
  FileUtils.rm_rf("#{tools_path}/dockerd-manifest.yml")
  FileUtils.rm_rf("#{tools_path}/docker-config-manifest.yml")
  stdout_success "Testsuite helper tools uninstalled."
end

desc "Deletes the tools the suite downloaded for itself (kubescape, kyverno CLI and policies, helm, chaos experiments); the next run downloads them again"
task "tools_purge" do |_, args|
  FileUtils.rm_rf(tools_path)
  stdout_success "Testsuite local tool downloads deleted."
end

desc "Cleans up the CNF and the helper tools the suite deployed into the cluster; keeps the suite's local downloads (see tools_purge)"
task "uninstall_all", ["cnf_uninstall", "tools_uninstall"] do |_, args|
end

desc "Deletes all results files from the results directory"
task "delete_results" do |_, args|
  files = Dir.glob(File.join(CNFManager::Points::Results.dir, "cnti-testsuite-results-*.yml"))
  files.each { |f| File.delete(f) }
  File.delete?(CNFManager::Points::Results.latest)
  Log.info { "Deleted #{files.size} results file(s)" }
  stdout_success "Deleted #{files.size} results file(s)."
end
