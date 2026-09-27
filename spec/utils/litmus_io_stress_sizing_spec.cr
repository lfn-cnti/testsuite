require "../spec_helper"
require "../../src/tasks/utils/litmus_manager.cr"

# The pod_io_stress file is sized as a percentage of the free space of the
# container's root filesystem, and only when that filesystem is memory backed:
# on a tmpfs root the file is charged to the CNF's memory limit as shmem, and a
# percentage computed from a limit the parser did not understand would leave the
# fault unbounded, which is what OOM-killed the NFs.
describe "LitmusManager.memory_quantity_bytes" do
  it "parses a plain byte count", tags: ["pod_io_stress"] do
    LitmusManager.memory_quantity_bytes("1048576").should eq(1024_i64 * 1024)
  end

  it "parses binary suffixes", tags: ["pod_io_stress"] do
    LitmusManager.memory_quantity_bytes("64Mi").should eq(64_i64 * 1024 * 1024)
    LitmusManager.memory_quantity_bytes("1Gi").should eq(1024_i64 * 1024 * 1024)
    LitmusManager.memory_quantity_bytes("2Ti").should eq(2_i64 * 1024 * 1024 * 1024 * 1024)
  end

  it "parses decimal suffixes", tags: ["pod_io_stress"] do
    LitmusManager.memory_quantity_bytes("500M").should eq(500_000_000_i64)
    LitmusManager.memory_quantity_bytes("2G").should eq(2_000_000_000_i64)
  end

  it "parses the decimal fractions Kubernetes allows on a memory limit", tags: ["pod_io_stress"] do
    # These are the values that used to fall through to the unbounded default.
    LitmusManager.memory_quantity_bytes("1.5Gi").should eq(1610612736_i64)
    LitmusManager.memory_quantity_bytes("0.5Gi").should eq(536870912_i64)
    LitmusManager.memory_quantity_bytes("1.5G").should eq(1_500_000_000_i64)
  end

  it "tolerates whitespace before the suffix", tags: ["pod_io_stress"] do
    LitmusManager.memory_quantity_bytes("128 Mi").should eq(134217728_i64)
  end

  it "is nil for a value it cannot parse", tags: ["pod_io_stress"] do
    LitmusManager.memory_quantity_bytes("").should be_nil
    LitmusManager.memory_quantity_bytes("unlimited").should be_nil
    LitmusManager.memory_quantity_bytes("64MB").should be_nil
  end
end

describe "LitmusManager.pod_io_stress_percentage" do
  # The percentage of the free space stress-ng turns into the stress file. A
  # tmpfs root is memory backed, so the file is charged to the CNF, and the
  # percentage has to keep the file under what is left of the memory limit.
  it "keeps the stress file under what is left of the memory limit", tags: ["pod_io_stress"] do
    # 56 MiB of budget over a 64 MiB tmpfs: 87%, which stress-ng turns into a
    # file of at most the budget.
    budget = 56_i64 * 1024 * 1024
    free = 64_i64 * 1024 * 1024
    LitmusManager.pod_io_stress_percentage(budget, free).should eq("87")
    (free * 87 // 100).should be <= budget
  end

  it "never exceeds the ceiling", tags: ["pod_io_stress"] do
    # An unbounded budget over a small tmpfs would be 100% or more; the
    # ceiling keeps the fault from aiming at filling the whole filesystem.
    LitmusManager.pod_io_stress_percentage(1024_i64 * 1024 * 1024, 1024_i64 * 1024).should eq("90")
  end

  it "floors below a whole percent rather than exceeding the budget", tags: ["pod_io_stress"] do
    # 1% of a 1 GiB tmpfs is 10 MiB, above an 8 MiB budget, so 1% would bring
    # the OOM race back. stress-ng keeps the percentage as a whole number, so
    # 0.5% is floored to 0 and stress-ng clamps the file up to its own 1 MiB
    # minimum, which is the smallest real stress the fault can express.
    free = 1024_i64 * 1024 * 1024
    budget = 8_i64 * 1024 * 1024
    (free * 1 // 100).should be > budget
    LitmusManager.pod_io_stress_percentage(budget, free).should eq("0.5")
  end

  it "never sends a percentage litmus reads as unset", tags: ["pod_io_stress"] do
    # litmus maps a literal "0" to its own 10% default, so a floor of "0"
    # would stress 10% of a large tmpfs rather than the 1 MiB minimum, which
    # is how the budget gets blown. The floor has to stay fractional.
    LitmusManager::MIN_FILESYSTEM_UTILIZATION_PERCENTAGE.should_not eq("0")
    LitmusManager::MIN_FILESYSTEM_UTILIZATION_PERCENTAGE.to_f64.should be > 0
  end

  it "is nil when the budget is smaller than the file stress-ng always creates", tags: ["pod_io_stress"] do
    # No percentage of the free space can produce a file under 1 MiB, so there
    # is no safe stress left to inject and the test reports not applicable
    # rather than stressing a container that is already out of memory.
    free = 64_i64 * 1024 * 1024
    LitmusManager.pod_io_stress_percentage(0_i64, free).should be_nil
    LitmusManager.pod_io_stress_percentage(LitmusManager::MIN_STRESS_NG_FILE_BYTES - 1, free).should be_nil
    LitmusManager.pod_io_stress_percentage(LitmusManager::MIN_STRESS_NG_FILE_BYTES, free).should eq("1")
  end

  it "uses the whole budget when the free space is exactly the budget", tags: ["pod_io_stress"] do
    LitmusManager.pod_io_stress_percentage(64_i64 * 1024 * 1024, 64_i64 * 1024 * 1024).should eq("90")
  end
end
