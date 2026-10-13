require "./example_cnf_validation"

# MongoDB Controllers for Kubernetes and a MongoDBCommunity replica set: the
# example of a CNF an operator deploys (#2361). The suite has to find the
# workloads through the custom resource's owner references.
describe "MongoDB operator validation" do
  before_all do
    ShellCmd.run_testsuite("setup")
  end

  # Not certified yet: 13 of 19 essential tests pass with the operator's
  # 1.13.0 chart. The fixes are open upstream (mongodb/mongodb-kubernetes#1698,
  # #1699 and #1700, 16 of 19 with all three); until then the run must reach a
  # verdict without an errored test.
  it "should install the MongoDB operator and a replica set and reach a cert verdict", tags: ["mongodb-operator_cert"] do
    ExampleCNFValidation.cert("./example-cnfs/mongodb-operator/cnti-testsuite.yaml", require_pass: false)
  end

  it "should run the full workload suite against the MongoDB operator and its replica set", tags: ["mongodb-operator_workload"] do
    ExampleCNFValidation.workload("./example-cnfs/mongodb-operator/cnti-testsuite.yaml")
  end

  after_all do
    ShellCmd.run_testsuite("uninstall_all")
  end
end
