require "../spec_helper"
require "../../src/tasks/utils/litmus_manager.cr"

# disk_fill and pod_io_stress write into the target container's root file
# system, and litmus defaults to the pod's first container. The helper names a
# writable container for the engine, or nil when every container is read-only.
describe "LitmusManager.filesystem_fault_target" do
  it "is nil when every container mounts a read-only root file system", tags: ["disk_fill", "pod_io_stress"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "mongodb", "securityContext": {"readOnlyRootFilesystem": true}},
        {"name": "sidecar", "securityContext": {"readOnlyRootFilesystem": true}}
      ]
    JSON
    LitmusManager.filesystem_fault_target(containers).should be_nil
  end

  it "names the writable container even when it is not the first one", tags: ["disk_fill", "pod_io_stress"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "mongodb", "securityContext": {"readOnlyRootFilesystem": true}},
        {"name": "amf", "securityContext": {"allowPrivilegeEscalation": false}}
      ]
    JSON
    LitmusManager.filesystem_fault_target(containers).should eq("amf")
  end

  it "names a container that has no securityContext at all", tags: ["disk_fill", "pod_io_stress"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "amf"}
      ]
    JSON
    LitmusManager.filesystem_fault_target(containers).should eq("amf")
  end

  it "names a container that explicitly keeps the root file system writable", tags: ["disk_fill", "pod_io_stress"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "webui", "securityContext": {"readOnlyRootFilesystem": false}}
      ]
    JSON
    LitmusManager.filesystem_fault_target(containers).should eq("webui")
  end

  it "is nil for an empty container list", tags: ["disk_fill", "pod_io_stress"] do
    LitmusManager.filesystem_fault_target(JSON.parse("[]")).should be_nil
  end
end
