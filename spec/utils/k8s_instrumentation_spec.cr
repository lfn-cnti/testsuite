require "../spec_helper"
require "../../src/tasks/utils/k8s_instrumentation.cr"
require "file_utils"
require "sam"

describe "K8sInstrumentation" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "'#disk_speed' should return all responses for the sysbench disk speed call on a pod", tags: ["k8s-instrumentation"]  do
    ClusterTools.install
    resp = K8sInstrumentation.disk_speed
    (resp["95th percentile"]).should_not be_nil
    (resp["95th percentile"].to_f).should_not be_nil
  end

end
