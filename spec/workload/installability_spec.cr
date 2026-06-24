require "../spec_helper"
require "colorize"

def verify_task_result(task_name : String, expected_status : String)
  latest_results = Dir.glob("results/cnf-testsuite-results-*.yml").max_by { |path| File.info(path).modification_time }
  latest_results.should_not be_nil
  yaml = YAML.parse(File.read(latest_results.not_nil!))
  item = yaml["items"].as_a.find { |i| i["name"].as_s == task_name }
  item.should_not be_nil
  item.not_nil!["status"].as_s.should eq(expected_status)
end

describe CnfTestSuite do
  before_all do
    result = ShellCmd.run_testsuite("setup")
  end


  it "'helm_deploy' should fail on a manifest CNF", tags: ["helm_validation"] do
    ShellCmd.cnf_install("cnf-path=./sample-cnfs/k8s-non-helm")
    result = ShellCmd.run_testsuite("helm_deploy")
    result[:status].success?.should be_true
    (/(FAILED).*(CNF has deployments that are not installed with helm)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'helm_deploy' should fail if command is not supplied cnf-config argument", tags: ["helm_validation"] do
    result = ShellCmd.run_testsuite("helm_deploy")
    result[:status].success?.should be_true
    (/No cnf_testsuite.yml found! Did you run the \"cnf_install\" task?/ =~ result[:output]).should_not be_nil
  end

  it "'helm_chart_valid' should pass on a good helm chart", tags: ["helm_validation"]  do
    ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
    result = ShellCmd.run_testsuite("helm_chart_valid")
    result[:status].success?.should be_true
    (/Helm chart lint passed on all charts/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'helm_chart_valid' should pass on a good helm chart with additional values file", tags: ["helm_validation"]  do
    ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_conditional_values_file/cnf-testsuite.yml")
    result = ShellCmd.run_testsuite("helm_chart_valid")
    result[:status].success?.should be_true
    (/Helm chart lint passed on all charts/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'helm_chart_valid' should fail on a bad helm chart", tags: ["helm_validation"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-bad_helm_coredns-cnf/cnf-testsuite.yml skip_wait_for_install", expect_failure: true)
      result = ShellCmd.run_testsuite("helm_chart_valid")
      result[:status].success?.should be_true
      (/Helm chart lint failed on one or more charts/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'helm_chart_published' should pass on a good helm chart repo", tags: ["helm_validation"]  do
    begin
      ShellCmd.cnf_install("cnf-path=sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("helm_chart_published")
      result[:status].success?.should be_true
      (/(PASSED).*(All Helm charts are published)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'helm_chart_published' should fail on a bad helm chart repo", tags: ["helm_validation"] do
    begin
      result = ShellCmd.run("helm search repo stable/coredns", force_output: true)
      ShellCmd.cnf_install("cnf-path=sample-cnfs/sample-bad-helm-repo skip_wait_for_install", expect_failure: true)
      result = ShellCmd.run("helm search repo stable/coredns", force_output: true)
      result = ShellCmd.run_testsuite("helm_chart_published")
      result[:status].success?.should be_true
      (/(FAILED).*(One or more Helm charts are not published)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.run("#{Helm::Binary.get} repo remove badrepo")
      result = ShellCmd.cnf_uninstall()
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
