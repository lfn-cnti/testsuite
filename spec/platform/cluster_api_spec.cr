require "./../spec_helper"
require "file_utils"
require "../../src/tasks/utils/utils.cr"

describe "Platform" do
  describe "cluster_api_enabled", tags: ["cluster-api"] do
    before_all do
      result = ShellCmd.run_testsuite("setup")
      result[:status].success?.should be_true
    end

    # (rafal-lal) TODO: decide how to proceed with Cluster API test case
    # after_each do
    #   result = ShellCmd.run_testsuite("uninstall_cluster_api")
    #   result[:status].success?.should be_true
    # end

    it "should pass if nodes are managed by Cluster API" do
      begin
        node_name = KubectlClient::Get.resource("nodes").dig("items").as_a.first.dig("metadata", "name").as_s
        KubectlClient::Utils.annotate("node", node_name, ["cluster.x-k8s.io/owner-name=test-cluster-quickstart",
                                                          "cluster.x-k8s.io/machine=test-1",
                                                          "cluster.x-k8s.io/cluster-name=test-cluster"])
      rescue ex : Exception
        ex.message.should be_nil
      end
      result = ShellCmd.run_testsuite("cluster_api_enabled poc")
      (/At least one node in the cluster is managed by Cluster API/ =~ result[:output]).should_not be_nil
    ensure
      # (rafal-lal) TODO: decide how to proceed with Cluster API test case
      # result = ShellCmd.run_testsuite("uninstall_cluster_api")
      begin
        node_name = KubectlClient::Get.resource("nodes").dig("items").as_a.first.dig("metadata", "name").as_s
        KubectlClient::Utils.annotate("node", node_name, ["cluster.x-k8s.io/owner-name-",
                                                          "cluster.x-k8s.io/machine-",
                                                          "cluster.x-k8s.io/cluster-name-"])
      rescue Exception
      end
    end

    it "should fail if nodes are not managed by Cluster API" do
      result = ShellCmd.run_testsuite("cluster_api_enabled poc")
      (/No nodes in the cluster are managed by Cluster API/ =~ result[:output]).should_not be_nil
    ensure
      # (rafal-lal) TODO: decide how to proceed with Cluster API test case
      # result = ShellCmd.run_testsuite("uninstall_cluster_api")
    end
  end
end
