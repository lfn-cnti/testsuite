require "../spec_helper.cr"

describe "KubectlClient::Get.replica_counts" do
  it "reads a scaled-to-zero StatefulSet, whose status leaves readyReplicas out, as 0 of 0", tags: ["points"] do
    json = JSON.parse(%({"kind": "StatefulSet", "status": {"replicas": 0, "availableReplicas": 0}}))
    KubectlClient::Get.replica_counts("StatefulSet", json).should eq({current: 0, desired: 0, unavailable: -1})
  end

  it "reads a scaled-to-zero Deployment, whose status has neither replicas nor readyReplicas, as 0 of 0", tags: ["points"] do
    json = JSON.parse(%({"kind": "Deployment", "spec": {"replicas": 0}, "status": {"observedGeneration": 1, "conditions": [{"type": "Available", "status": "True"}]}}))
    KubectlClient::Get.replica_counts("Deployment", json).should eq({current: 0, desired: 0, unavailable: -1})
  end

  it "reads a Deployment with no ready pod yet as 0 of its replicas", tags: ["points"] do
    json = JSON.parse(%({"kind": "Deployment", "status": {"replicas": 3, "unavailableReplicas": 3}}))
    KubectlClient::Get.replica_counts("Deployment", json).should eq({current: 0, desired: 3, unavailable: 3})
  end

  it "reads the counts of a ready Deployment", tags: ["points"] do
    json = JSON.parse(%({"kind": "Deployment", "status": {"replicas": 2, "readyReplicas": 2}}))
    KubectlClient::Get.replica_counts("Deployment", json).should eq({current: 2, desired: 2, unavailable: -1})
  end

  it "reports -1 while the controller has not written a status yet", tags: ["points"] do
    json = JSON.parse(%({"kind": "Deployment", "spec": {"replicas": 1}}))
    KubectlClient::Get.replica_counts("Deployment", json).should eq({current: -1, desired: -1, unavailable: -1})
  end

  it "reports -1 for a DaemonSet the controller has not observed yet, whose status the API server set to zeros", tags: ["points"] do
    json = JSON.parse(%({"kind": "DaemonSet", "metadata": {"generation": 1}, "status": {"currentNumberScheduled": 0, "desiredNumberScheduled": 0, "numberMisscheduled": 0, "numberReady": 0}}))
    KubectlClient::Get.replica_counts("DaemonSet", json).should eq({current: -1, desired: -1, unavailable: -1})
  end

  it "reads a DaemonSet the controller has observed and no node schedules as 0 of 0", tags: ["points"] do
    json = JSON.parse(%({"kind": "DaemonSet", "metadata": {"generation": 1}, "status": {"observedGeneration": 1, "currentNumberScheduled": 0, "desiredNumberScheduled": 0, "numberMisscheduled": 0, "numberReady": 0}}))
    KubectlClient::Get.replica_counts("DaemonSet", json).should eq({current: 0, desired: 0, unavailable: -1})
  end

  it "reports -1 while the controller has not observed a Deployment's newest spec", tags: ["points"] do
    json = JSON.parse(%({"kind": "Deployment", "metadata": {"generation": 2}, "spec": {"replicas": 3}, "status": {"observedGeneration": 1, "replicas": 2, "readyReplicas": 2}}))
    KubectlClient::Get.replica_counts("Deployment", json).should eq({current: -1, desired: -1, unavailable: -1})
  end

  it "reads the counts once the controller has observed the newest spec", tags: ["points"] do
    json = JSON.parse(%({"kind": "StatefulSet", "metadata": {"generation": 3}, "status": {"observedGeneration": 3, "replicas": 2, "readyReplicas": 1}}))
    KubectlClient::Get.replica_counts("StatefulSet", json).should eq({current: 1, desired: 2, unavailable: -1})
  end

  it "reads a DaemonSet with nothing scheduled as 0 of 0", tags: ["points"] do
    json = JSON.parse(%({"kind": "DaemonSet", "status": {"desiredNumberScheduled": 0, "numberReady": 0}}))
    KubectlClient::Get.replica_counts("DaemonSet", json).should eq({current: 0, desired: 0, unavailable: -1})
  end
end
