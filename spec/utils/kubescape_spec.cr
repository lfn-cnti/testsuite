require "../spec_helper"
require "../../src/tasks/utils/kubescape.cr"
require "../../src/tasks/utils/utils.cr"

describe "K8sInstrumentation" do
  before_all do
    result = ShellCmd.run_testsuite("setup:install_kubescape")
  end

  it "'#scan and #test_by_test_name' should return the results of a kubescape scan", tags: ["kubescape"]  do
    ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_coredns/cnf-testsuite.yml")
    Kubescape.scan
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Network policies")
    (test_json).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

end
