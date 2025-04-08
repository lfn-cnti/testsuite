require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Resilience pod dns error Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "'pod_dns_error' A 'Good' CNF should not crash when pod dns error occurs", tags: ["pod_dns_error"]  do
    begin
      ShellCmd.cnf_install("cnf-config=example-cnfs/envoy/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("pod_dns_error")
      result[:status].success?.should be_true
      ((/(SKIPPED).*(pod_dns_error docker runtime not found)/)  =~ result[:output] || 
       (/(PASSED).*(pod_dns_error chaos test passed)/ =~ result[:output])).should_not be_nil
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
end
