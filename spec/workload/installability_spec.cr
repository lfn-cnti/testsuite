require "../spec_helper"
require "colorize"

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
      result = ShellCmd.run("#{Helm::BinarySingleton.helm} repo remove badrepo")
      result = ShellCmd.cnf_uninstall()
    end
  end
end
