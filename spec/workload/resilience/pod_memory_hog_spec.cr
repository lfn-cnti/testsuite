require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Resilience pod memory hog Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result = ShellCmd.run_testsuite("setup:configuration_file_setup")
    result[:status].success?.should be_true
  end

  it "'pod_memory_hog' A 'Good' CNF should not crash when pod memory hog occurs", tags: ["pod_memory_hog"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("pod_memory_hog")
      result[:status].success?.should be_true
      (/(PASSED).*(pod_memory_hog chaos test passed)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("uninstall_litmus")
      result[:status].success?.should be_true
    end
  end
end
