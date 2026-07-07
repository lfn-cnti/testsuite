require "spec"
require "colorize"
require "../src/cnf_testsuite"
require "../src/tasks/utils/utils.cr"
require "../src/modules/tar"
require "../src/modules/git"
require "../src/modules/release_manager"
require "../src/modules/kernel_introspection"
require "../src/modules/docker_client"
require "../src/modules/helm"
require "../src/modules/k8s_kernel_introspection"
require "../src/modules/k8s_netstat"
require "../src/modules/cluster_tools"
require "../src/modules/kubectl_client"

ENV["CRYSTAL_ENV"] = "TEST" 


# Skip the build when a caller (e.g. CI) has already built the binary and sets
# CNF_TESTSUITE_SKIP_BUILD, avoiding a redundant full recompile per spec run.
# The skip only applies when the binary is actually present.
if ENV["CNF_TESTSUITE_SKIP_BUILD"]? && File.exists?("./cnf-testsuite")
  Log.info { "Skipping ./cnf-testsuite build (CNF_TESTSUITE_SKIP_BUILD set)".colorize(:green) }
else
  Log.info { "Building ./cnf-testsuite".colorize(:green) }
  result = ShellCmd.run("crystal build --warnings none src/cnf-testsuite.cr")
  if result[:status].success?
    Log.info { "Build Success!".colorize(:green) }
  else
    Log.info { "crystal build failed!".colorize(:red) }
    raise "crystal build failed in spec_helper"
  end
end

module ShellCmd
  def self.run_testsuite(testsuite_cmd, cmd_prefix="")
    cmd = "#{cmd_prefix} ./cnf-testsuite #{testsuite_cmd}"
    run(cmd, log_prefix: "ShellCmd.run_testsuite", force_output: true, joined_output: true)
  end

  def self.cnf_install(install_params, timeout=300, cmd_prefix="", expect_failure=false)
    result = run_testsuite("cnf_install #{install_params} timeout=#{timeout}", cmd_prefix)
    if !expect_failure
      result[:status].success?.should be_true
    else
      result[:status].success?.should be_false
    end
    result
  end

  def self.cnf_uninstall(timeout=300, cmd_prefix="", expect_failure=false)
    result = run_testsuite("cnf_uninstall timeout=#{timeout}", cmd_prefix)
    if !expect_failure
      result[:status].success?.should be_true
    else
      result[:status].success?.should be_false
    end
    result
  end
end

# Asserts that the most recent results file contains an item for the given task
# with the expected status. Shared by the workload specs.
def verify_task_result(task_name : String, expected_status : String)
  latest_results = Dir.glob("results/cnf-testsuite-results-*.yml").max_by { |path| File.info(path).modification_time }
  latest_results.should_not be_nil
  yaml = YAML.parse(File.read(latest_results.not_nil!))
  item = yaml["items"].as_a.find { |i| i["name"].as_s == task_name }
  item.should_not be_nil
  item.not_nil!["status"].as_s.should eq(expected_status)
end
