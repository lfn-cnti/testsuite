require "../spec_helper"

private def items(json : String) : Array(JSON::Any)
  JSON.parse(json).as_a
end

describe "FailureDiagnostics" do
  it "sees a pod that could not be scheduled, with its requests and the largest node", tags: ["points"] do
    pods = items(%([{"metadata": {"name": "web-0", "namespace": "cnf"}, "status": {"phase": "Pending"},
      "spec": {"containers": [{"name": "web", "resources": {"requests": {"cpu": "4", "memory": "2Gi"}}}]}}]))
    events = items(%([{"reason": "FailedScheduling", "type": "Warning",
      "message": "0/1 nodes are available: 1 Insufficient cpu.",
      "involvedObject": {"kind": "Pod", "name": "web-0", "namespace": "cnf"}}]))
    nodes = items(%([{"metadata": {"name": "small"}, "status": {"allocatable": {"cpu": "2", "memory": "4Gi"},
      "conditions": [{"type": "Ready", "status": "True"}]}}]))

    conditions = FailureDiagnostics.detect(pods, events, nodes)

    conditions.size.should eq(1)
    conditions[0].kind.should eq("scheduling_failed")
    conditions[0].object.should eq("Pod/web-0 in cnf")
    conditions[0].detail.should eq("0/1 nodes are available: 1 Insufficient cpu. (requests cpu=4000m memory=2048Mi; largest node allocatable cpu=2 memory=4Gi (small))")
  end

  it "sees an image that could not be pulled, once per container", tags: ["points"] do
    pods = items(%([{"metadata": {"name": "web-0", "namespace": "cnf"}, "status": {"phase": "Pending",
      "containerStatuses": [{"name": "web", "image": "example.invalid/web:1",
        "state": {"waiting": {"reason": "ImagePullBackOff", "message": "Back-off pulling image \\"example.invalid/web:1\\"\\nmore"}}}]}}]))

    conditions = FailureDiagnostics.detect(pods, [] of JSON::Any, [] of JSON::Any)

    conditions.map(&.to_h).should eq([{"kind" => "image_pull_failed", "object" => "Pod/web-0 in cnf",
                                       "detail" => %(container web image example.invalid/web:1: ImagePullBackOff: Back-off pulling image "example.invalid/web:1")}])
  end

  it "sees a pod whose sandbox was never created, and that it has no events", tags: ["points"] do
    pods = items(%([{"metadata": {"name": "upf-0", "namespace": "cnf"}, "spec": {"nodeName": "worker"},
      "status": {"phase": "Pending", "conditions": [{"type": "PodReadyToStartContainers", "status": "False"}]}}]))

    conditions = FailureDiagnostics.detect(pods, [] of JSON::Any, [] of JSON::Any)

    conditions.map(&.to_h).should eq([{"kind" => "pod_sandbox_not_created", "object" => "Pod/upf-0 in cnf",
                                       "detail" => "PodReadyToStartContainers=False on node worker, no events since the test started"}])
  end

  it "matches pods and events by namespace as well as name", tags: ["points"] do
    pods = items(%([{"metadata": {"name": "web-0", "namespace": "a"}, "status": {"phase": "Pending",
        "conditions": [{"type": "PodReadyToStartContainers", "status": "False"}]}},
      {"metadata": {"name": "web-0", "namespace": "b"}, "status": {"phase": "Pending"},
        "spec": {"containers": [{"name": "web", "resources": {"requests": {"cpu": "1"}}}]}}]))
    events = items(%([{"reason": "FailedScheduling", "message": "0/1 nodes are available.",
      "involvedObject": {"kind": "Pod", "name": "web-0", "namespace": "b"}}]))

    conditions = FailureDiagnostics.detect(pods, events, [] of JSON::Any).map(&.to_h)

    conditions.should contain({"kind" => "pod_sandbox_not_created", "object" => "Pod/web-0 in a",
                               "detail" => "PodReadyToStartContainers=False, no events since the test started"})
    conditions.should contain({"kind" => "scheduling_failed", "object" => "Pod/web-0 in b",
                               "detail" => "0/1 nodes are available. (requests cpu=1000m memory=0Mi)"})
  end

  it "sees nodes not Ready or under pressure, and pods evicted", tags: ["points"] do
    nodes = items(%([{"metadata": {"name": "worker"}, "status": {"conditions": [
      {"type": "Ready", "status": "False", "reason": "KubeletNotReady"},
      {"type": "DiskPressure", "status": "True"},
      {"type": "MemoryPressure", "status": "False"}]}}]))
    events = items(%([{"reason": "Evicted", "message": "The node was low on resource: ephemeral-storage.",
      "involvedObject": {"kind": "Pod", "name": "web-0", "namespace": "cnf"}}]))

    conditions = FailureDiagnostics.detect([] of JSON::Any, events, nodes).map(&.to_h)

    conditions.should eq([
      {"kind" => "node_not_ready", "object" => "Node/worker", "detail" => "Ready=False (KubeletNotReady)"},
      {"kind" => "node_pressure", "object" => "Node/worker", "detail" => "DiskPressure=True"},
      {"kind" => "node_pressure", "object" => "Pod/web-0 in cnf", "detail" => "evicted: The node was low on resource: ephemeral-storage."},
    ])
  end

  it "sees nothing in a healthy cluster", tags: ["points"] do
    pods = items(%([{"metadata": {"name": "web-0", "namespace": "cnf"}, "status": {"phase": "Running",
      "conditions": [{"type": "PodReadyToStartContainers", "status": "True"}],
      "containerStatuses": [{"name": "web", "state": {"running": {}}}]}}]))
    nodes = items(%([{"metadata": {"name": "worker"}, "status": {"conditions": [{"type": "Ready", "status": "True"}]}}]))

    FailureDiagnostics.detect(pods, [] of JSON::Any, nodes).should be_empty
  end

  it "captures an object without managedFields, the last applied configuration and literal env values", tags: ["points"] do
    object = JSON.parse(%({"kind": "Deployment", "metadata": {"name": "web", "managedFields": [{}],
      "annotations": {"kubectl.kubernetes.io/last-applied-configuration": "{}", "team": "a"}},
      "spec": {"template": {"spec": {"containers": [{"name": "web", "env": [
        {"name": "PASSWORD", "value": "hunter2"},
        {"name": "TOKEN", "valueFrom": {"secretKeyRef": {"name": "s", "key": "k"}}}]}]}}}}))

    redacted = FailureDiagnostics.redact(object)

    redacted.dig("metadata").as_h.has_key?("managedFields").should be_false
    redacted.dig("metadata", "annotations").as_h.should eq({"team" => JSON::Any.new("a")})
    env = redacted.dig("spec", "template", "spec", "containers", 0, "env")
    env[0]["value"].should eq("***")
    env[1].dig("valueFrom", "secretKeyRef", "name").should eq("s")
    redacted.to_json.should_not contain("hunter2")
  end

  it "cuts a capture to its size limit, logs first, and says what it cut", tags: ["points"] do
    log = (1..100).map { |i| "line #{i}\n" }.join
    sections = {
      "test"   => JSON::Any.new("node_drain"),
      "logs"   => JSON.parse({"cnf/web-0/web" => log}.to_json),
      "events" => JSON.parse((1..400).map { |i| {"reason" => "BackOff", "message" => "x" * 100, "n" => i} }.to_json),
      "pods"   => JSON::Any.new([] of JSON::Any),
    }

    document = JSON.parse(FailureDiagnostics.fit(sections, 20_000))

    document.to_json.bytesize.should be <= 20_000
    document["truncated"].as_a.map(&.as_s).should eq(["logs cut to 10 lines per container", "events cut to the last 50"])
    document["logs"]["cnf/web-0/web"].as_s.should eq((91..100).map { |i| "line #{i}\n" }.join)
    document["events"].as_a.size.should eq(50)
    document["events"][0]["n"].should eq(351)
  end
end
