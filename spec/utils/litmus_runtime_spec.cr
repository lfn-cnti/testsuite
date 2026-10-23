require "../spec_helper"
require "../../src/tasks/utils/litmus_manager.cr"

# The litmus chaos helpers exec into the target container through the node's
# container runtime, so the chaos engine must advertise the runtime and its
# socket path. Unsupported runtimes must resolve to nil so the task reports
# not applicable instead of arming the experiment with a containerd socket.
describe "LitmusManager.detect_runtime" do
  it "picks the first supported runtime among the nodes", tags: ["pod_io_stress"] do
    LitmusManager.detect_runtime(["fancyruntime://1.0.0", "containerd://2.0.2", "docker://27.3.1"]).should eq("containerd")
  end

  it "is nil when no node runs a supported runtime", tags: ["pod_io_stress"] do
    LitmusManager.detect_runtime(["fancyruntime://1.0.0"]).should be_nil
    LitmusManager.detect_runtime([] of String).should be_nil
  end
end

describe "LitmusManager.detect_runtime_socket" do
  it "honours the environment override without probing the cluster", tags: ["pod_io_stress"] do
    ENV[LitmusManager::RUNTIME_SOCKET_ENV] = "/custom/containerd.sock"
    LitmusManager.detect_runtime_socket("containerd").should eq("/custom/containerd.sock")
  ensure
    ENV.delete(LitmusManager::RUNTIME_SOCKET_ENV)
  end
end

describe "LitmusManager.runtime_socket_for" do
  it "maps docker to the docker socket", tags: ["pod_io_stress"] do
    LitmusManager.runtime_socket_for("docker://27.3.1").should eq({"docker", "/var/run/docker.sock"})
  end

  it "maps containerd to the containerd socket", tags: ["pod_io_stress"] do
    LitmusManager.runtime_socket_for("containerd://2.0.2").should eq({"containerd", "/run/containerd/containerd.sock"})
  end

  it "maps cri-o to the cri-o socket", tags: ["pod_io_stress"] do
    LitmusManager.runtime_socket_for("cri-o://1.31.1").should eq({"crio", "/var/run/crio/crio.sock"})
  end

  it "is nil for an unknown runtime", tags: ["pod_io_stress"] do
    LitmusManager.runtime_socket_for("fancyruntime://1.0.0").should be_nil
    LitmusManager.runtime_socket_for("").should be_nil
  end

  it "tolerates a runtime version without the '://' separator", tags: ["pod_io_stress"] do
    LitmusManager.runtime_socket_for("containerd").should eq({"containerd", "/run/containerd/containerd.sock"})
  end
end

describe "LitmusManager.chaos_charts" do
  it "takes a mirror from the environment without its trailing slash", tags: ["points"] do
    ENV[LitmusManager::CHAOS_CHARTS_ENV] = "https://mirror.example/chaos-charts/"
    LitmusManager.chaos_charts.should eq("https://mirror.example/chaos-charts")
  ensure
    ENV.delete(LitmusManager::CHAOS_CHARTS_ENV)
  end

  it "uses the versioned chaos-charts tree when no mirror is set", tags: ["points"] do
    ENV.delete(LitmusManager::CHAOS_CHARTS_ENV)
    LitmusManager.chaos_charts.should eq(LitmusManager::CHAOS_CHARTS)
  end
end
