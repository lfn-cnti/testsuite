require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Resilience Node Drain Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result = ShellCmd.run_testsuite("configuration_file_setup")
    result[:status].success?.should be_true
  end

  it "'node_drain' A 'Good' CNF should not crash when node drain occurs", tags: ["node_drain"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("node_drain")
      result[:status].success?.should be_true
      if KubectlClient::Get.schedulable_nodes_list.size > 1
        (/(PASSED).*(node_drain chaos test passed)/ =~ result[:output]).should_not be_nil
      else
        (/(SKIPPED).*(node_drain chaos test requires the cluster to have atleast two)/ =~ result[:output]).should_not be_nil
      end
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("uninstall_litmus")
      result[:status].success?.should be_true
    end
  end
end
