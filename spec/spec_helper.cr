require "spec"
require "colorize"
require "../src/cnti_testsuite"
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

ENV["CNTI_TESTSUITE_ENV"] = "TEST"

# Specs assume no CNF is installed; a leftover installation can make them fail
# in ways that are hard to trace back to the environment.
if Dir.exists?(CNF_DIR)
  Log.warn { "A CNF appears to be installed ('#{CNF_DIR}' directory present). Spec tests assume a clean environment and may behave unexpectedly. Consider running './cnti-testsuite cnf_uninstall' first.".colorize(:yellow) }
end

# Skip the build when a caller (e.g. CI) has already built the binary and sets
# CNTI_TESTSUITE_SKIP_BUILD, avoiding a redundant full recompile per spec run.
# The skip only applies when the binary is actually present.
if ENV["CNTI_TESTSUITE_SKIP_BUILD"]? && File.exists?("./cnti-testsuite")
  Log.info { "Skipping ./cnti-testsuite build (CNTI_TESTSUITE_SKIP_BUILD set)".colorize(:green) }
else
  Log.info { "Building ./cnti-testsuite".colorize(:green) }
  result = ShellCmd.run("crystal build --warnings none src/cnti-testsuite.cr")
  if result[:status].success?
    Log.info { "Build Success!".colorize(:green) }
  else
    Log.info { "crystal build failed!".colorize(:red) }
    raise "crystal build failed in spec_helper"
  end
end

module ShellCmd
  def self.run_testsuite(testsuite_cmd, cmd_prefix = "")
    cmd = "#{cmd_prefix} ./cnti-testsuite #{testsuite_cmd}"
    run_live(cmd, log_prefix: "ShellCmd.run_testsuite")
  end

  # A failed install or uninstall fails the example with the suite's own
  # output, so CI logs show why rather than just `Expected: true, got: false`.
  private def self.expect_outcome(result, command : String, expect_failure : Bool)
    if !expect_failure && !result[:status].success?
      fail "#{command} failed (exit #{result[:status].exit_code}):\n#{result[:output]}"
    elsif expect_failure && result[:status].success?
      fail "#{command} succeeded but was expected to fail:\n#{result[:output]}"
    end
  end

  # Echoes the suite's stdout (and stderr) to the spec runner line by line as
  # it is produced, instead of buffering it until the process ends, so CI logs
  # fill up live while a long suite (install/cert/workload) runs. The full
  # output is still captured for assertions.
  private def self.run_live(cmd, log_prefix = "ShellCmd.run_live")
    log = Log.for(log_prefix)
    log.info { "command: #{cmd}" }
    # `2>&1` in the shell keeps stdout and stderr in the single pipe read
    # below, so the echo order matches what a direct run would print.
    process = Process.new("#{cmd} 2>&1", shell: true, output: Process::Redirect::Pipe)
    output = IO::Memory.new
    drained = Channel(Nil).new
    spawn do
      while line = process.output.gets
        puts line
        output << line << '\n'
      end
      drained.send(nil)
    end
    status = process.wait
    drained.receive
    {status: status, output: output.to_s, error: ""}
  end

  def self.cnf_install(install_params, timeout = 300, cmd_prefix = "", expect_failure = false)
    result = run_testsuite("cnf_install #{install_params} --timeout #{timeout}", cmd_prefix)
    expect_outcome(result, "cnf_install #{install_params}", expect_failure)
    result
  end

  def self.cnf_uninstall(timeout = 300, cmd_prefix = "", expect_failure = false)
    result = run_testsuite("cnf_uninstall --timeout #{timeout}", cmd_prefix)
    expect_outcome(result, "cnf_uninstall", expect_failure)
    result
  end
end

# Asserts that the most recent results file contains an item for the given task
# with the expected status. Shared by the workload specs.
def verify_task_result(task_name : String, expected_status : String)
  latest_results = CNFManager::Points::Results.latest
  File.exists?(latest_results).should be_true
  yaml = YAML.parse(File.read(latest_results))
  item = yaml["items"].as_a.find { |i| i["name"].as_s == task_name }
  item.should_not be_nil
  item.not_nil!["status"].as_s.should eq(expected_status)
end
