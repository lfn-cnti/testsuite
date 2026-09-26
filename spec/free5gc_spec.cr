require "./example_cnf_validation"

# Each chaos test runs one experiment per workload, about 27 minutes for
# free5GC's fifteen. In one job the workload suite would take about four and
# a quarter hours on a GitHub-hosted runner, close to the six a hosted job
# may run once a test is slow. Three chaos tests get a job of their own:
# the workload job then takes about three hours and this one an hour and a
# half.
FREE5GC_LONG_CHAOS = ["pod_network_latency", "pod_network_corruption", "pod_memory_hog"]

describe "free5GC validation" do
  before_all do
    ShellCmd.run_testsuite("setup")
  end

  it "should successfully install and pass certification tests for free5GC", tags: ["free5gc_cert"] do
    ExampleCNFValidation.cert("./example-cnfs/free5gc/cnti-testsuite.yaml")
  end

  it "should run the workload suite against free5GC, but for the long chaos tests", tags: ["free5gc_workload"] do
    ExampleCNFValidation.workload("./example-cnfs/free5gc/cnti-testsuite.yaml", skip: FREE5GC_LONG_CHAOS)
  end

  it "should run the long chaos tests against free5GC", tags: ["free5gc_long_chaos"] do
    ExampleCNFValidation.tests("./example-cnfs/free5gc/cnti-testsuite.yaml", FREE5GC_LONG_CHAOS)
  end

  after_all do
    ShellCmd.run_testsuite("uninstall_all")
  end
end
