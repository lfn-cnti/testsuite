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
