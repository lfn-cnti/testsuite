require "../spec_helper"
require "../../src/tasks/utils/litmus_manager.cr"

# pod_io_stress writes its stress file to the container's root filesystem. On a
# memory-backed tmpfs root the file is charged to the CNF's memory limit as
# shmem, so a bounded write would stress memory and a pass would say nothing
# about I/O. The test reports that as not applicable instead.
describe "LitmusManager.pod_io_stress_memory_backed_reason" do
  it "reports a tmpfs root as memory backed", tags: ["pod_io_stress"] do
    reason = LitmusManager.pod_io_stress_memory_backed_reason("upf", "tmpfs")
    reason.should_not be_nil
    reason.not_nil!.should contain("upf")
    reason.not_nil!.should contain("memory backed (tmpfs)")
    reason.not_nil!.should contain("instead of stressing I/O")
  end

  it "leaves a disk-backed root to the default size", tags: ["pod_io_stress"] do
    LitmusManager.pod_io_stress_memory_backed_reason("upf", "ext4").should be_nil
    LitmusManager.pod_io_stress_memory_backed_reason("upf", "xfs").should be_nil
    LitmusManager.pod_io_stress_memory_backed_reason("upf", "overlay").should be_nil
  end
end
