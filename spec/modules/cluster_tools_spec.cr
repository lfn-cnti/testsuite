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

describe "ClusterTools" do
  before_all do
    KubectlClient::Apply.namespace(ClusterTools.namespace)
  end

  after_all do
    ClusterTools.uninstall
  end

  # A unit spec: no cluster is asked anything, so it runs with the other
  # unit specs.
  it "names a container ID of another runtime as the reason it cannot be inspected, without asking the node", tags: ["points"] do
    node = JSON.parse(%({"metadata": {"name": "node-1"}}))
    looked_up = ClusterTools.pid_or_reason("cri-o://0123456789abcdef", node)
    looked_up[:pid].should be_nil
    looked_up[:reason].should eq("container ID cri-o://0123456789abcdef is a cri-o ID; the suite inspects containers through containerd only")
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

describe "ClusterTools.crictl_error" do
  it "takes the message of crictl's fatal line and drops its warnings", tags: ["points"] do
    stderr = <<-'ERR'
      time="2026-10-23T10:00:00Z" level=warning msg="runtime connect using default endpoints: [unix:///run/containerd/containerd.sock]"
      time="2026-10-23T10:00:00Z" level=fatal msg="getting the status of the container \"abc\": rpc error: code = NotFound desc = an error occurred when try to find container \"abc\": not found"
      ERR
    ClusterTools.crictl_error(stderr).should eq(%q(getting the status of the container "abc": rpc error: code = NotFound desc = an error occurred when try to find container "abc": not found))
  end

  it "keeps a plain stderr line, then stdout, when there is no logrus error", tags: ["points"] do
    ClusterTools.crictl_error("E1023 10:00:00 remote_runtime.go:1] ContainerStatus failed\n").should eq("E1023 10:00:00 remote_runtime.go:1] ContainerStatus failed")
    ClusterTools.crictl_error(%q(time="x" level=warning msg="default endpoints"), "exec failed\n").should eq("exec failed")
    ClusterTools.crictl_error("", "").should eq("no output")
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
