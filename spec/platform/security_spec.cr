require "./../spec_helper"
require "colorize"
require "./../../src/tasks/utils/utils.cr"

describe "Platform" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "'control_plane_hardening' should pass if the control plane has been hardened", tags: ["platform:security"] do
    result = ShellCmd.run_testsuite("platform:control_plane_hardening")
    (/(PASSED).*(Insecure port of Kubernetes API server is not enabled)/ =~ result[:output]).should_not be_nil
  end

  it "'cluster_admin' should fail on a cnf that uses a cluster admin binding", tags: ["platform:security"] do
    begin
      result = ShellCmd.run_testsuite("platform:cluster_admin")
      result[:status].success?.should be_true
      (/(FAILED).*(Users with cluster-admin RBAC permissions found)/ =~ result[:output]).should_not be_nil
    end
  end

  it "'helm_tiller' should fail if Helm Tiller is running in the cluster", tags: ["platform:security"] do
    ShellCmd.run("kubectl run tiller --image=rancher/tiller:v2.11.0", "create_tiller")
    KubectlClient::Wait.resource_wait_for_install("pod", "tiller")
    result = ShellCmd.run_testsuite("platform:helm_tiller")
    result[:status].success?.should be_true
    (/(FAILED).*(Containers with the Helm Tiller image are running)/ =~ result[:output]).should_not be_nil
  ensure
    KubectlClient::Delete.resource("pod", "tiller")
    KubectlClient::Wait.resource_wait_for_uninstall("pod", "tiller")
  end

  it "'helm_tiller' should fail if Helm Tiller is running in the cluster", tags: ["platform:security"] do
    # By default we have nothing to setup for this task to pass since Helm v3 does not use Tiller.
    result = ShellCmd.run_testsuite("platform:helm_tiller")
    result[:status].success?.should be_true
    (/(PASSED).*(No Helm Tiller containers are running)/ =~ result[:output]).should_not be_nil
  end
end
