require "../spec_helper"
require "../../src/tasks/utils/chaos_templates.cr"

# In-process, no cluster: every engine whose helper goes through the container
# runtime names the runtime and socket it was given (#2103).
describe "Chaos engines and the container runtime" do
  it "render the runtime and socket of the cluster, not containerd's", tags: ["points"] do
    engines = {
      "pod-network-latency"     => ChaosTemplates::PodNetworkLatency.new("t", "pod-network-latency", "ns", "deployment", "app", "web", container_runtime: "crio", socket_path: "/var/run/crio/crio.sock").to_s,
      "pod-network-corruption"  => ChaosTemplates::PodNetworkCorruption.new("t", "pod-network-corruption", "ns", "deployment", "app", "web", container_runtime: "crio", socket_path: "/var/run/crio/crio.sock").to_s,
      "pod-network-duplication" => ChaosTemplates::PodNetworkDuplication.new("t", "pod-network-duplication", "ns", "deployment", "app", "web", container_runtime: "crio", socket_path: "/var/run/crio/crio.sock").to_s,
      "pod-memory-hog"          => ChaosTemplates::PodMemoryHog.new("t", "pod-memory-hog", "ns", "deployment", "app", "web", "", container_runtime: "crio", socket_path: "/var/run/crio/crio.sock").to_s,
      "pod-dns-error"           => ChaosTemplates::PodDnsError.new("t", "pod-dns-error", "ns", "deployment", "app", "web", container_runtime: "crio", socket_path: "/var/run/crio/crio.sock").to_s,
      "pod-io-stress"           => ChaosTemplates::PodIoStress.new("t", "pod-io-stress", "ns", "deployment", "app", "web", "", container_runtime: "crio", socket_path: "/var/run/crio/crio.sock").to_s,
    }
    engines.each do |name, engine|
      parsed = YAML.parse(engine)
      env = parsed.dig("spec", "experiments", 0, "spec", "components", "env").as_a
      values = env.to_h { |e| {e["name"].as_s, e["value"]?.to_s} }
      {name, values["CONTAINER_RUNTIME"]?}.should eq({name, "crio"})
      {name, values["SOCKET_PATH"]?}.should eq({name, "/var/run/crio/crio.sock"})
    end
  end
end
