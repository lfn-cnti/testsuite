require "../spec_helper"
require "../../src/tasks/utils/litmus_manager.cr"

# The litmus chaos helpers exec into the target container through the node's
# container runtime, so the chaos engine must advertise the runtime and its
# socket path. Unsupported runtimes must resolve to nil so the task can skip
# instead of arming the experiment with a hard-coded containerd socket.
describe "LitmusManager.runtime_socket_for" do
  it "maps docker to the docker socket", tags: ["points"] do
    LitmusManager.runtime_socket_for("docker://27.3.1").should eq({"docker", "/var/run/docker.sock"})
  end

  it "maps containerd to the containerd socket", tags: ["points"] do
    LitmusManager.runtime_socket_for("containerd://2.0.2").should eq({"containerd", "/run/containerd/containerd.sock"})
  end

  it "maps cri-o to the cri-o socket", tags: ["points"] do
    LitmusManager.runtime_socket_for("cri-o://1.31.1").should eq({"crio", "/var/run/crio/crio.sock"})
  end

  it "is nil for an unknown runtime", tags: ["points"] do
    LitmusManager.runtime_socket_for("fancyruntime://1.0.0").should be_nil
    LitmusManager.runtime_socket_for("").should be_nil
  end

  it "tolerates a runtime version without the '://' separator", tags: ["points"] do
    LitmusManager.runtime_socket_for("containerd").should eq({"containerd", "/run/containerd/containerd.sock"})
  end
end