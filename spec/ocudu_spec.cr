require "./example_cnf_validation"

describe "OCUDU validation" do
  before_all do
    ShellCmd.run_testsuite("setup")
  end

  it "should successfully install and pass certification tests for OCUDU", tags: ["ocudu_cert"] do
    ExampleCNFValidation.cert("./example-cnfs/ocudu/cnti-testsuite.yaml")
  end

  it "should run the full workload suite against OCUDU", tags: ["ocudu_workload"] do
    ExampleCNFValidation.workload("./example-cnfs/ocudu/cnti-testsuite.yaml")
  end

  after_all do
    ShellCmd.run_testsuite("uninstall_all")
  end
end
