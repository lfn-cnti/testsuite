require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Resilience Node Drain" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end


  it "'node_drain' A 'Good' CNF should not crash when node drain occurs", tags: ["node_drain"]  do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("node_drain")
      result[:status].success?.should be_true
      if KubectlClient::Get.schedulable_nodes_list.size > 1
        (/(PASSED).*(node_drain passed: 1 node\(s\) drained, 1 workload\(s\) rescheduled)/ =~ result[:output]).should_not be_nil
        (/> Node \S+: 1 pod\(s\) of 1 workload\(s\) evicted in \d+ s/ =~ result[:output]).should_not be_nil
        (/> Deployment\/coredns-coredns in cnti-default: Ready again on another node \d+ s after eviction/ =~ result[:output]).should_not be_nil
        verify_task_result("node_drain", "passed")
      else
        (/(SKIPPED).*(node_drain requires at least two schedulable nodes)/ =~ result[:output]).should_not be_nil
        verify_task_result("node_drain", "skipped")
      end
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
