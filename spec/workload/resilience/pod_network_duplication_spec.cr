require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Resilience Pod Network duplication Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result = ShellCmd.run_testsuite("setup:configuration_file_setup")
    result[:status].success?.should be_true
  end


  it "'pod_network_duplication' A 'Good' CNF should not crash when network duplication occurs", tags: ["pod_network_duplication"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("pod_network_duplication")
      result[:status].success?.should be_true
      (/(PASSED).*(pod_network_duplication chaos test passed)/ =~ result[:output]).should_not be_nil
      verify_task_result("pod_network_duplication", "passed")
    rescue ex
      # Raise back error to ensure test fails.
      # The ensure block will uninstall the CNF and Litmus.
      raise "Test failed with #{ex.message}"
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("uninstall_litmus")
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
