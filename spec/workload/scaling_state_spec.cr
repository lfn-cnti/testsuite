require "../spec_helper.cr"
require "../../src/tasks/**"

# What increase_decrease_capacity reads while it waits for a scale: the ready
# count, and the replica count the spec asks for now, which tells an operator
# or an autoscaler setting it back from the target (#2899).
describe "scaling_state" do
  it "reads the ready count and the spec's replica count once the controller observed the spec", tags: ["points"] do
    live = JSON.parse(%({"kind": "Deployment", "metadata": {"generation": 2}, "spec": {"replicas": 4}, "status": {"observedGeneration": 2, "replicas": 4, "readyReplicas": 2}}))
    scaling_state(live, "Deployment").should eq({ready: 2, spec: 4})
  end

  it "does not know the ready count while the controller has not observed the scaled spec", tags: ["points"] do
    live = JSON.parse(%({"kind": "Deployment", "metadata": {"generation": 2}, "spec": {"replicas": 4}, "status": {"observedGeneration": 1, "replicas": 2, "readyReplicas": 2}}))
    scaling_state(live, "Deployment").should eq({ready: -1, spec: 4})
  end

  it "shows the spec set back from the target", tags: ["points"] do
    live = JSON.parse(%({"kind": "StatefulSet", "metadata": {"generation": 3}, "spec": {"replicas": 2}, "status": {"observedGeneration": 3, "replicas": 2, "readyReplicas": 2}}))
    scaling_state(live, "StatefulSet").should eq({ready: 2, spec: 2})
  end

  it "takes an unset spec.replicas as one", tags: ["points"] do
    live = JSON.parse(%({"kind": "Deployment", "metadata": {"generation": 1}, "status": {"observedGeneration": 1, "replicas": 1, "readyReplicas": 1}}))
    scaling_state(live, "Deployment").should eq({ready: 1, spec: 1})
  end
end

describe "ScaleOutcome#ready_s" do
  it "names an unknown ready count rather than printing -1", tags: ["points"] do
    ScaleOutcome.new(-1, false, 4).ready_s.should eq("none yet")
    ScaleOutcome.new(3, false, 4).ready_s.should eq("3")
  end
end

describe "judge_scale" do
  label = "Deployment/web in cnti-default"

  it "counts a scale that reached its target with the spec still asking for it", tags: ["points"] do
    judge_scale(ScaleOutcome.new(4, false, 4), 2, 4, nil, label).verdict.should eq(:scaled)
  end

  it "never counts a reverted scale as a success, even while the ready count still shows the target", tags: ["points"] do
    # A Deployment's ready count comes from its ReplicaSets: after the spec is
    # set back to 2, it can read 4 for a moment.
    judge_scale(ScaleOutcome.new(4, true, 2), 2, 4, nil, label).verdict.should eq(:failed)
    judge_scale(ScaleOutcome.new(4, true, 2), 2, 4, "MongoDBCommunity/mongodb", label).verdict.should eq(:operator_owned)
  end

  it "names an operator-owned workload whose owner set the count back, and does not fail it", tags: ["points"] do
    j = judge_scale(ScaleOutcome.new(2, true, 2), 2, 4, "MongoDBCommunity/mongodb", label)
    j.verdict.should eq(:operator_owned)
    j.detail.should eq("#{label}: owned by MongoDBCommunity/mongodb, which sets its replica count; a direct scale to 4 was set back to 2, so it is not counted")
  end

  it "names an operator-owned workload whose owner let the count stand but never got the pods there", tags: ["points"] do
    judge_scale(ScaleOutcome.new(2, false, 4), 2, 4, "MongoDBCommunity/mongodb", label).detail
      .should contain("a direct scale to 4 did not take (2 ready), so it is not counted")
  end

  it "fails a workload nobody owns whose target was set back, with that reason", tags: ["points"] do
    j = judge_scale(ScaleOutcome.new(2, true, 2), 2, 4, nil, label)
    j.verdict.should eq(:failed)
    j.detail.should eq("#{label}: increase from 2 to 4 replicas was set back to 2 while scaling")
    j.reason.should eq("could not scale up to 4 replicas (set back to 2)")
  end

  it "fails a scale that ran out of time, with the ready count", tags: ["points"] do
    j = judge_scale(ScaleOutcome.new(3, false, 4), 2, 4, nil, label)
    j.detail.should eq("#{label}: increase from 2 to 4 replicas did not complete (3 ready)")
    j.reason.should eq("could not scale up to 4 replicas (3 ready)")
  end

  it "words the scale back down the other way round", tags: ["points"] do
    j = judge_scale(ScaleOutcome.new(-1, false, 2), 4, 2, nil, label)
    j.detail.should eq("#{label}: decrease from 4 back to 2 replicas did not complete (none yet ready)")
    j.reason.should eq("could not scale back down to 2 replicas (none yet ready)")
  end
end
