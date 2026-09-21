require "../spec_helper"
require "../../src/tasks/utils/litmus_manager.cr"

# The litmus disk-fill (dd) and pod-io-stress (fio) helpers write a file into
# the target container's root file system, so a container with
# readOnlyRootFilesystem set can never be injected against ("Read-only file
# system" / "exit status 1"); such containers must be skipped by the disk_fill
# and pod_io_stress tasks instead of being scored as failures.
describe "LitmusManager.filesystem_fault_injectable?" do
  it "is false when every container mounts a read-only root file system", tags: ["points"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "mongodb", "securityContext": {"readOnlyRootFilesystem": true}},
        {"name": "sidecar", "securityContext": {"readOnlyRootFilesystem": true}}
      ]
    JSON
    LitmusManager.filesystem_fault_injectable?(containers).should be_false
  end

  it "is true when at least one container keeps a writable root file system", tags: ["points"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "mongodb", "securityContext": {"readOnlyRootFilesystem": true}},
        {"name": "amf", "securityContext": {"allowPrivilegeEscalation": false}}
      ]
    JSON
    LitmusManager.filesystem_fault_injectable?(containers).should be_true
  end

  it "is true when a container has no securityContext at all", tags: ["points"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "amf"}
      ]
    JSON
    LitmusManager.filesystem_fault_injectable?(containers).should be_true
  end

  it "is true when a container explicitly keeps the root file system writable", tags: ["points"] do
    containers = JSON.parse(<<-JSON)
      [
        {"name": "webui", "securityContext": {"readOnlyRootFilesystem": false}}
      ]
    JSON
    LitmusManager.filesystem_fault_injectable?(containers).should be_true
  end

  it "keeps the historical behavior of running the fault when the container list is empty or not a list", tags: ["points"] do
    LitmusManager.filesystem_fault_injectable?(JSON.parse("[]")).should be_true
    LitmusManager.filesystem_fault_injectable?(JSON.parse("{}")).should be_true
  end
end
