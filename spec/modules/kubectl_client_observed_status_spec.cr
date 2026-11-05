require "../spec_helper.cr"
require "../../src/tasks/**"

# Status read before a controller has observed the newest spec, outside the
# install wait: the count increase_decrease_capacity restarts a DaemonSet by,
# and a custom resource's Ready condition.
describe "CapacityRestart.scheduled_nodes" do
  pod_on = ->(node : String) { JSON.parse(%({"spec": {"nodeName": "#{node}"}})) }

  it "takes the desired count of a DaemonSet its controller has observed", tags: ["points"] do
    ds = JSON.parse(%({"kind": "DaemonSet", "metadata": {"generation": 1}, "status": {"observedGeneration": 1, "desiredNumberScheduled": 2, "numberReady": 2}}))
    CapacityRestart.scheduled_nodes(ds, [pod_on.call("a"), pod_on.call("b"), pod_on.call("c")]).should eq(2)
  end

  it "counts the pods bound to a node while the status is the API server's zeros", tags: ["points"] do
    ds = JSON.parse(%({"kind": "DaemonSet", "metadata": {"generation": 1}, "status": {"desiredNumberScheduled": 0, "numberReady": 0}}))
    unbound = JSON.parse(%({"spec": {}}))
    CapacityRestart.scheduled_nodes(ds, [pod_on.call("a"), pod_on.call("b"), unbound]).should eq(2)
  end

  it "does not know the count while the DaemonSet is unobserved and no pod is bound to a node", tags: ["points"] do
    ds = JSON.parse(%({"kind": "DaemonSet", "metadata": {"generation": 2}, "status": {"observedGeneration": 1, "desiredNumberScheduled": 3, "numberReady": 3}}))
    CapacityRestart.scheduled_nodes(ds, [JSON.parse(%({"spec": {}}))]).should be_nil
  end

  it "reads 0 for an observed DaemonSet that no node schedules", tags: ["points"] do
    ds = JSON.parse(%({"kind": "DaemonSet", "metadata": {"generation": 1}, "status": {"observedGeneration": 1, "desiredNumberScheduled": 0, "numberReady": 0}}))
    CapacityRestart.scheduled_nodes(ds, [] of JSON::Any).should eq(0)
  end
end

describe "KubectlClient::Wait.condition_stale?" do
  it "is stale when the condition's observedGeneration is behind the resource's generation", tags: ["points"] do
    cr = JSON.parse(%({"metadata": {"generation": 3}}))
    KubectlClient::Wait.condition_stale?(cr, JSON.parse(%({"type": "Ready", "status": "True", "observedGeneration": 2}))).should be_true
  end

  it "is current when the condition observed the resource's generation", tags: ["points"] do
    cr = JSON.parse(%({"metadata": {"generation": 3}}))
    KubectlClient::Wait.condition_stale?(cr, JSON.parse(%({"type": "Ready", "status": "True", "observedGeneration": 3}))).should be_false
  end

  it "says nothing about a condition without observedGeneration", tags: ["points"] do
    cr = JSON.parse(%({"metadata": {"generation": 3}}))
    KubectlClient::Wait.condition_stale?(cr, JSON.parse(%({"type": "Ready", "status": "True"}))).should be_false
  end
end

describe "KubectlClient::Wait.custom_resource_json_ready?" do
  cr = ->(observed : Int32, status : String) do
    JSON.parse(%({"metadata": {"generation": 3}, "status": {"conditions": [{"type": "Ready", "status": "#{status}", "observedGeneration": #{observed}}]}}))
  end

  it "is not ready while its Ready condition describes an earlier generation", tags: ["points"] do
    KubectlClient::Wait.custom_resource_json_ready?(cr.call(2, "True")).should be_false
  end

  it "is ready once its Ready condition observed the current generation", tags: ["points"] do
    KubectlClient::Wait.custom_resource_json_ready?(cr.call(3, "True")).should be_true
  end

  it "is not ready on a current Ready condition that is False", tags: ["points"] do
    KubectlClient::Wait.custom_resource_json_ready?(cr.call(3, "False")).should be_false
  end

  it "is ready once it exists when it reports no conditions", tags: ["points"] do
    KubectlClient::Wait.custom_resource_json_ready?(JSON.parse(%({"metadata": {"generation": 1}}))).should be_true
  end
end
