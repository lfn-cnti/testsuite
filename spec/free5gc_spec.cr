require "./example_cnf_validation"

describe "free5GC validation" do
  before_all do
    ShellCmd.run_testsuite("setup")
  end

  it "should successfully install and pass certification tests for free5GC", tags: ["free5gc_cert"] do
    ExampleCNFValidation.cert("./example-cnfs/free5gc/cnti-testsuite.yaml")
  end

  it "should run the full workload suite against free5GC", tags: ["free5gc_workload"] do
    ExampleCNFValidation.workload("./example-cnfs/free5gc/cnti-testsuite.yaml")
  end

  after_all do
    ShellCmd.run_testsuite("uninstall_all")
  end
end
