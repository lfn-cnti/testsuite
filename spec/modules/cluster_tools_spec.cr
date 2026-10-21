require "../spec_helper.cr"

# Builds a minimal fake node JSON whose status.images contains:
#   - one sha256 entry: "registry/org/image@sha256:<digest>"
#   - one tag entry:    "registry/org/image:<tag>"
private def mock_nodes(registry_image : String, tag : String, digest : String) : Array(JSON::Any)
  node_json = <<-JSON
    {
      "status": {
        "images": [
          {
            "names": [
              "#{registry_image}@#{digest}",
              "#{registry_image}:#{tag}"
            ],
            "sizeBytes": 12345
          }
        ]
      }
    }
  JSON
  [JSON.parse(node_json)]
end

describe "ClusterTools.local_match_by_image_name" do
  digest = "sha256:7d727245767ae632eb296c2ff4d206bf2e205b5f244c1f37b8fdd61f9fb33985"
  other_digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  nodes = mock_nodes("cr.fluentbit.io/fluent/fluent-bit", "latest", digest)

  it "returns found=true when image_name has tag+digest and digest matches a node imageID", tags: ["local_match_by_image_name"] do
    match = ClusterTools.local_match_by_image_name("fluent/fluent-bit:latest@#{digest}", nodes)
    match[:found].should be_true
    match[:digest].should eq(digest)
  end

  it "returns found=true when image_name has digest only (no tag) and digest matches a node imageID", tags: ["local_match_by_image_name"] do
    match = ClusterTools.local_match_by_image_name("fluent/fluent-bit@#{digest}", nodes)
    match[:found].should be_true
    match[:digest].should eq(digest)
  end

  it "returns found=false when image_name has tag+digest but digest does NOT match any node imageID", tags: ["local_match_by_image_name"] do
    match = ClusterTools.local_match_by_image_name("fluent/fluent-bit:latest@#{other_digest}", nodes)
    match[:found].should be_false
  end

  it "returns found=false when image_name has no tag and no digest and no image is present on nodes", tags: ["local_match_by_image_name"] do
    match = ClusterTools.local_match_by_image_name("some/unknown-image", [] of JSON::Any)
    match[:found].should be_false
  end
end

describe "ClusterTools.harness_failure?" do
  it "tells a failed runtime lookup apart from a container the runtime does not know", tags: ["harness_failure"] do
    # The runtime's own answer for a container it does not know: the CNF's
    # container is gone, which is a finding about the CNF.
    ClusterTools.harness_failure?("rpc error: code = NotFound desc = an error occurred when try to find container \"abc123\": not found").should be_false
    # A command that did not reach the runtime: the suite cannot judge the
    # CNF, which is a finding about the harness.
    ClusterTools.harness_failure?("failed to connect to /run/containerd/containerd.sock: no such file or directory").should be_true
    ClusterTools.harness_failure?("error: unable to upgrade connection: container not found (pod \"cluster-tools-xyz\")").should be_true
    ClusterTools.harness_failure?("no cluster-tools pod on node worker-1").should be_true
    ClusterTools.harness_failure?("the runtime of the node did not answer").should be_true
    ClusterTools.harness_failure?("error: unable to upgrade connection: rpc error: code = DeadlineExceeded desc = context deadline exceeded").should be_true
  end

  it "has no opinion about a reason that is not there", tags: ["harness_failure"] do
    ClusterTools.harness_failure?(nil).should be_false
    ClusterTools.harness_failure?("").should be_false
  end
end

describe "ClusterTools::InspectionOutcome" do
  it "keeps the reasons and tells a harness failure from a missing container", tags: ["inspection_outcome"] do
    outcome = ClusterTools::InspectionOutcome.new
    outcome.empty?.should be_true
    outcome.harness_broken.should be_false

    outcome.add("pod-x container app: the runtime does not know the container")
    outcome.empty?.should be_false
    outcome.harness_broken.should be_false

    outcome.add("pod-x container app: failed to connect to the runtime socket")
    outcome.harness_broken.should be_true
    outcome.reasons.size.should eq(2)
  end
end

describe "ClusterTools" do
  before_all do
    KubectlClient::Apply.namespace(ClusterTools.namespace)
  end

  after_all do
    ClusterTools.uninstall
  end

  it "ensure_namespace_exists!", tags:["cluster_tools"] do
    (ClusterTools.ensure_namespace_exists!).should be_true

    KubectlClient::Delete.resource("namespace", "#{ClusterTools.namespace}")

    expect_raises(ClusterTools::NamespaceDoesNotExistException, "ClusterTools Namespace #{ClusterTools.namespace} does not exist") do
      ClusterTools.ensure_namespace_exists!
    end
  end

  it "install", tags:["cluster_tools"] do
    KubectlClient::Apply.namespace(ClusterTools.namespace)

    (ClusterTools.install).should be_true

    (ClusterTools.ensure_namespace_exists!).should be_true
  end

  it "ensure_namespace_exists! (post install)", tags:["cluster_tools"] do
    ClusterTools.install
    (ClusterTools.ensure_namespace_exists!).should be_true
  end

  it "pod_name", tags:["cluster_tools"] do
    (/cluster-tools/ =~ ClusterTools.pod_name).should_not be_nil
  end
end

describe "ClusterTools.running_pid_from_inspect" do
  it "returns the PID of a running container", tags: ["points"] do
    ClusterTools.running_pid_from_inspect(%({"info": {"pid": 4242}})).should eq("4242")
  end

  it "returns nil for an exited container, whose pid crictl reports as 0 (#2802)", tags: ["points"] do
    ClusterTools.running_pid_from_inspect(%({"info": {"pid": 0}})).should be_nil
  end

  it "returns nil when there is no pid or no valid JSON", tags: ["points"] do
    ClusterTools.running_pid_from_inspect(%({"info": {}})).should be_nil
    ClusterTools.running_pid_from_inspect("not json").should be_nil
  end
end
