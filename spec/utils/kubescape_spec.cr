require "../spec_helper"
require "../../src/tasks/utils/kubescape.cr"
require "../../src/tasks/utils/utils.cr"

describe "K8sInstrumentation" do
  before_all do
    result = ShellCmd.run_testsuite("setup:install_kubescape")
  end

  it "'#control_policy_file' extracts a control from the downloaded bundle and rejects an unknown one", tags: ["kubescape"] do
    path = Kubescape.control_policy_file("C-0048")
    File.exists?(path).should be_true
    JSON.parse(File.read(path))["controlID"].should eq("C-0048")
    expect_raises(Kubescape::ScanError, /C-9999 is not in the kubescape allcontrols framework/) do
      Kubescape.control_policy_file("C-9999")
    end
  end

  it "'#parse' raises a ScanError instead of a parse error when the report is missing or empty", tags: ["kubescape"] do
    expect_raises(Kubescape::ScanError, /no kubescape report/) { Kubescape.parse("#{tools_path}/kubescape/does-not-exist.json") }
    empty = "#{tools_path}/kubescape/empty-report.json"
    File.write(empty, "")
    expect_raises(Kubescape::ScanError, /no kubescape report/) { Kubescape.parse(empty) }
  ensure
    File.delete?("#{tools_path}/kubescape/empty-report.json")
  end

  it "'#scan' of a single control reads the control offline and reports it", tags: ["kubescape"] do
    ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml")
    Kubescape.scan(control_id: "C-0048")
    results_json = Kubescape.parse(Kubescape.control_results_file("C-0048"))
    Kubescape.test_by_test_name(results_json, "HostPath mount")["name"].should eq("HostPath mount")
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'#scan and #test_by_test_name' should return the results of a kubescape scan", tags: ["kubescape"]  do
    ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml")
    Kubescape.scan
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Network policies")
    (test_json).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

end
