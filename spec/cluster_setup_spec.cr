require "./spec_helper"
require "colorize"
require "../src/tasks/utils/utils.cr"

describe "Cluster Setup" do
  it "'install_cluster_tools' should create the cnti-testsuite namespace when it is missing", tags: ["cluster_setup"] do
    KubectlClient::Delete.resource("namespace", ClusterTools.namespace, extra_opts: "--ignore-not-found --wait")

    result = ShellCmd.run_testsuite("setup:install_cluster_tools")
    result[:status].success?.should be_true
    SuiteNamespaces.owned?(KubectlClient::Get.resource("namespace", ClusterTools.namespace)).should be_true
  ensure
    result = ShellCmd.run_testsuite("setup:uninstall_cluster_tools")
    result[:status].success?.should be_true
  end
end
