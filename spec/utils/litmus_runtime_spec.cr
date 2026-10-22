require "../spec_helper"
require "../../src/tasks/utils/litmus_manager.cr"
require "../../src/tasks/utils/chaos_templates.cr"

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

# Runs the block with the chaos-charts mirror set to `value` (unset when nil)
# and puts back whatever the environment held before.
private def with_chaos_charts_mirror(value : String?, &)
  previous = ENV[LitmusManager::CHAOS_CHARTS_ENV]?
  begin
    if value
      ENV[LitmusManager::CHAOS_CHARTS_ENV] = value
    else
      ENV.delete(LitmusManager::CHAOS_CHARTS_ENV)
    end
    yield
  ensure
    if previous
      ENV[LitmusManager::CHAOS_CHARTS_ENV] = previous
    else
      ENV.delete(LitmusManager::CHAOS_CHARTS_ENV)
    end
  end
end

describe "LitmusManager.chaos_charts" do
  it "takes a mirror from the environment without its trailing slash", tags: ["points"] do
    with_chaos_charts_mirror("https://mirror.example/chaos-charts/") do
      LitmusManager.chaos_charts.should eq("https://mirror.example/chaos-charts")
    end
  end

  it "uses the versioned chaos-charts tree when no mirror is set", tags: ["points"] do
    with_chaos_charts_mirror(nil) do
      LitmusManager.chaos_charts.should eq(LitmusManager::CHAOS_CHARTS)
    end
  end

  it "refuses a mirror that is not HTTPS before fetching anything", tags: ["points"] do
    with_chaos_charts_mirror("http://user:secret@mirror.example/chaos-charts") do
      ex = expect_raises(LitmusManager::FaultInstallError) do
        LitmusManager.install_fault("pod-delete", "default", "pod_delete")
      end
      message = ex.message.to_s
      message.should contain("#{LitmusManager::CHAOS_CHARTS_ENV} must be an https:// URL")
      message.should_not contain("secret")
    end
  end
end

# disk_fill's helper fills the target's directory under the runtime's
# container root, which depends on the runtime and the distribution (#2826).
describe "LitmusManager.detect_container_path" do
  it "honours the environment override without probing the cluster", tags: ["disk_fill"] do
    ENV[LitmusManager::CONTAINER_PATH_ENV] = "/custom/containers/"
    LitmusManager.detect_container_path("containerd").should eq("/custom/containers/")
  ensure
    ENV.delete(LitmusManager::CONTAINER_PATH_ENV)
  end

  it "has a container directory for every runtime the helpers understand", tags: ["disk_fill"] do
    LitmusManager::RUNTIME_SOCKET_CANDIDATES.keys.each do |runtime|
      LitmusManager::CONTAINER_PATH_CANDIDATES[runtime]?.should_not be_nil
    end
    LitmusManager::CONTAINER_PATH_CANDIDATES["containerd"].first.should eq("/var/lib/containerd/io.containerd.grpc.v1.cri/containers/")
  end
end

describe "ChaosTemplates::DiskFill" do
  it "names the runtime's container directory in the engine", tags: ["disk_fill"] do
    template = ChaosTemplates::DiskFill.new("engine", "disk-fill", "ns", "deployment", "app", "web",
      target_container: "web", container_path: "/var/lib/containers/storage/overlay-containers/").to_s
    template.should contain("- name: CONTAINER_PATH\n              value: '/var/lib/containers/storage/overlay-containers/'")
  end
end
