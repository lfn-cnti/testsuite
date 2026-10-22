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
        (/> Deployment\/coredns-coredns in cnti-default: Ready again on another node within \d+ s of eviction/ =~ result[:output]).should_not be_nil
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

  it "'node_drain' should not judge a workload whose volume the cluster's default storage class ties to the drained node", tags: ["node_drain"] do
    begin
      # A StatefulSet on the default storage class; on kind that is
      # local-path, whose volumes carry a node affinity.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-elastic-vct/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("node_drain")
      result[:status].success?.should be_true
      if KubectlClient::Get.schedulable_nodes_list.size > 1
        (/(N\/A).*(node_drain not applicable: every workload is tied to its node by the cluster's default storage class \(1 workload\(s\), see the details\))/ =~ result[:output]).should_not be_nil
        (/> StatefulSet\/sample-elastic-vct in cnti-default: cannot be rescheduled, its volume is tied to node \S+ by the cluster's default storage class \(claim data-sample-elastic-vct-0, PersistentVolume \S+: .+, provisioned by \S+ \(storage class standard\), the cluster's default\); not judged, it comes back when the node does/ =~ result[:output]).should_not be_nil
        (/remediation: The cluster's default storage class provisions volumes tied to one node/ =~ result[:output]).should_not be_nil
        verify_task_result("node_drain", "na")
        # And it did come back once the node was uncordoned.
        KubectlClient::Get.resource("statefulset", "sample-elastic-vct", DEFAULT_CNF_NAMESPACE).dig?("status", "readyReplicas").try(&.as_i).should eq(1)
      else
        verify_task_result("node_drain", "skipped")
      end
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'node_drain' should fail a workload the CNF itself pins to the drained node with a local PersistentVolume", tags: ["node_drain"] do
    schedulable = KubectlClient::Get.schedulable_nodes_list
    schedulable.should_not be_empty
    # The chart's PersistentVolume is a local volume pinned to a node the CNF names.
    update_yml("sample-cnfs/sample-local-storage/worker-node-value.yml", "worker_node", schedulable[0].dig("metadata", "name"))
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-local-storage/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("node_drain")
      if schedulable.size > 1
        result[:status].exit_code.should eq(1)
        (/(FAILED).*(node_drain failed: 1 workload\(s\) did not come back after a drain)/ =~ result[:output]).should_not be_nil
        (/impacted: Deployment\/coredns-coredns in cnti-default: not Ready within \d+s of eviction from node \S+/ =~ result[:output]).should_not be_nil
        # The scheduler's own words for it, which differ between versions.
        (/volume node affinity conflict|didn't match PersistentVolume's node affinity/ =~ result[:output]).should_not be_nil
        verify_task_result("node_drain", "failed")
      else
        verify_task_result("node_drain", "skipped")
      end
    ensure
      result = ShellCmd.cnf_uninstall()
      update_yml("sample-cnfs/sample-local-storage/worker-node-value.yml", "worker_node", "")
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
