require "../spec_helper"
require "../../src/tasks/**"

# The platform record of the results file: the cluster the tests ran on,
# parsed from kubectl's JSON. Needs no cluster.
describe "CNFManager::Platform" do
  nodes = JSON.parse(File.read("spec/fixtures/nodes-sample.json"))
  version = JSON.parse(%({"clientVersion":{"gitVersion":"v1.37.0"},"serverVersion":{"gitVersion":"v1.32.0","platform":"linux/amd64"}}))
  daemonsets = JSON.parse(%({"items":[{"metadata":{"name":"kindnet"}},{"metadata":{"name":"kube-proxy"}}]}))

  it "describes the cluster from kubectl's JSON", tags: ["points"] do
    record = CNFManager::Platform.from_json(version, nodes, daemonsets)
    record["kubernetes"].should eq("v1.32.0")
    record["provider"].should eq("kind")
    record["cni"].should eq("kindnet")
    nodes_out = record["nodes"].as(Array)
    nodes_out.size.should eq(2)
    control = nodes_out[0].as(Hash)
    control["name"].should eq("kind-control-plane")
    control["roles"].should eq(["control-plane"])
    control["kubelet"].should eq("v1.32.0")
    control["os_image"].should eq("Debian GNU/Linux 12 (bookworm)")
    control["kernel"].should eq("6.8.0-1017-azure")
    control["container_runtime"].should eq("containerd://1.7.24")
    control["architecture"].should eq("amd64")
    control["cpu"].should eq("4")
    control["memory"].should eq("16373844Ki")
    nodes_out[1].as(Hash)["roles"].should eq([] of String)
  end

  it "says what it cannot tell: no version, no CNI, no providerID", tags: ["points"] do
    bare = JSON.parse(%({"items":[{"metadata":{"name":"n1"},"spec":{},"status":{"nodeInfo":{"kubeletVersion":"v1.30.0"},"capacity":{"cpu":"2"}}}]}))
    record = CNFManager::Platform.from_json(nil, bare, nil)
    record["kubernetes"].should be_nil
    record["provider"].should eq("none")
    record["cni"].should be_nil
    node = record["nodes"].as(Array)[0].as(Hash)
    node["memory"].should eq("")
    node["kubelet"].should eq("v1.30.0")

    aws = JSON.parse(%({"items":[{"metadata":{"name":"n1"},"spec":{"providerID":"aws:///eu-west-1a/i-0123"},"status":{}}]}))
    CNFManager::Platform.from_json(nil, aws, nil)["provider"].should eq("aws")
  end

  # The results-file drift guard in cnf_manager_spec validates a fresh file,
  # platform block included, against docs/cnti-testsuite-results.schema.json.
  it "is in a fresh results file: the cluster at hand, or null", tags: ["points"] do
    CNFManager::Points.clean_results_yml
    doc = YAML.parse(File.read(CNFManager::Points::Results.file))
    doc.as_h.has_key?(YAML::Any.new("platform")).should be_true
    platform = doc["platform"]
    (platform.raw.nil? || !platform.as_h?.nil?).should be_true
    if (record = platform.as_h?)
      record.keys.map(&.as_s).sort.should eq(["cni", "kubernetes", "nodes", "provider"])
    end
  end

  it "'results_junit' prints the platform as properties", tags: ["points"] do
    results = YAML.parse(File.read("spec/fixtures/results-sample.yml"))
    results.as_h[YAML::Any.new("platform")] = YAML.parse(CNFManager::Platform.from_json(version, nodes, daemonsets).to_json)
    doc = XML.parse(JUnitReport.from_results(results))
    prop = ->(name : String) { doc.xpath_nodes("/testsuites/properties/property[@name='#{name}']").first["value"] }
    prop.call("platform.kubernetes").should eq("v1.32.0")
    prop.call("platform.provider").should eq("kind")
    prop.call("platform.cni").should eq("kindnet")
    prop.call("platform.nodes").should contain(%("name":"kind-worker"))
  end
end
