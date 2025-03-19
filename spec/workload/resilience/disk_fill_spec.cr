require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Resilience Disk Fill Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result = ShellCmd.run_testsuite("configuration_file_setup")
    result[:status].success?.should be_true
  end

  it "'disk_fill' A 'Good' CNF should not crash when disk fill occurs", tags: ["disk_fill"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml skip_wait_for_install")
      result = ShellCmd.run_testsuite("disk_fill")
      result[:status].success?.should be_true
      (/(PASSED).*(disk_fill chaos test passed)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall("timeout=0")
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("uninstall_litmus")
      result[:status].success?.should be_true
    end
  end
end
