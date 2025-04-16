require "./spec_helper"
require "colorize"
require "../src/tasks/utils/utils.cr"

describe "Cluster Setup" do
  it "'install_cluster_tools' should give a message if namespace does not exist", tags: ["cluster_setup"] do
    # TODO: add proper exception rescuing in all specs, rescue more specific Exception rather than generic one
    begin
      KubectlClient::Delete.resource("namespace", ClusterTools.namespace)
    rescue Exception
    end

    result = ShellCmd.run_testsuite("setup:install_cluster_tools")
    result[:status].success?.should be_false
    (/Error: Namespace cnf-testsuite does not exist./ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.run_testsuite("setup:uninstall_cluster_tools")
    result[:status].success?.should be_false
    (/Error: Namespace cnf-testsuite does not exist./ =~ result[:output]).should_not be_nil
  end

  it "'install_cluster_tools' should give a message if namespace does not exist even after dependency installation", tags: ["cluster_setup"] do
    result = ShellCmd.run_testsuite("setup")

    KubectlClient::Delete.resource("namespace", ClusterTools.namespace)

    result = ShellCmd.run_testsuite("setup:install_cluster_tools")
    result[:status].success?.should be_false
    (/Error: Namespace cnf-testsuite does not exist./ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.run_testsuite("setup:uninstall_cluster_tools")
    result[:status].success?.should be_false
    (/Error: Namespace cnf-testsuite does not exist./ =~ result[:output]).should_not be_nil
  end
end
