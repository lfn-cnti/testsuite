require "../spec_helper"
require "colorize"

describe CntiTestSuite do
  before_all do
    result = ShellCmd.run_testsuite("setup")
  end


  it "'helm_deploy' should fail on a manifest CNF", tags: ["helm_validation"] do
    ShellCmd.cnf_install("--cnf-config ./sample-cnfs/k8s-non-helm")
    result = ShellCmd.run_testsuite("helm_deploy")
    result[:status].exit_code.should eq(1)
    (/(FAILED).*(CNF has deployments that are not installed with helm)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'helm_deploy' should fail if command is not supplied cnf-config argument", tags: ["helm_validation"] do
    result = ShellCmd.run_testsuite("helm_deploy")
    result[:status].exit_code.should eq(1)
    (/No cnti-testsuite.yaml found! Did you run the \"cnf_install\" task?/ =~ result[:output]).should_not be_nil
  end

  it "'helm_chart_valid' should pass on a good helm chart", tags: ["helm_validation"]  do
    ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
    result = ShellCmd.run_testsuite("helm_chart_valid")
    result[:status].success?.should be_true
    (/Helm chart lint passed on all charts/ =~ result[:output]).should_not be_nil
    (/> chart coredns: lint passed/ =~ result[:output]).should_not be_nil
    verify_task_result("helm_chart_valid", "passed")
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'helm_chart_valid' should pass on a good helm chart with additional values file", tags: ["helm_validation"]  do
    ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_conditional_values_file/cnti-testsuite.yaml")
    result = ShellCmd.run_testsuite("helm_chart_valid")
    result[:status].success?.should be_true
    (/Helm chart lint passed on all charts/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'helm_chart_valid' should fail on a bad helm chart", tags: ["helm_validation"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-bad_helm_coredns-cnf/cnti-testsuite.yaml --skip-wait-for-install", expect_failure: true)
      result = ShellCmd.run_testsuite("helm_chart_valid")
      result[:status].exit_code.should eq(1)
      (/Helm chart lint failed on 1 chart\(s\)/ =~ result[:output]).should_not be_nil
      (/> chart bad-helm-coredns-coredns: lint failed: \[ERROR\] templates\/: parse error .* function "sdfskfsdf" not defined/ =~ result[:output]).should_not be_nil
      (/impacted: HelmChart\/bad-helm-coredns-coredns: \[ERROR\] templates\/: parse error/ =~ result[:output]).should_not be_nil
      verify_task_result("helm_chart_valid", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'helm_chart_published' should pass on a good helm chart repo", tags: ["helm_validation"]  do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("helm_chart_published")
      result[:status].success?.should be_true
      (/(PASSED).*(All Helm charts are published)/ =~ result[:output]).should_not be_nil
      (/> chart coredns: stable\/coredns found in repository https:\/\/cncf.gitlab.io\/stable \(chart version [\d.]+, app version [\d.]+\)/ =~ result[:output]).should_not be_nil
      verify_task_result("helm_chart_published", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'helm_chart_published' should fail on a bad helm chart repo", tags: ["helm_validation"] do
    begin
      result = ShellCmd.run("helm search repo stable/coredns", force_output: true)
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-bad-helm-repo --skip-wait-for-install", expect_failure: true)
      result = ShellCmd.run("helm search repo stable/coredns", force_output: true)
      result = ShellCmd.run_testsuite("helm_chart_published")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(1 Helm chart\(s\) not published)/ =~ result[:output]).should_not be_nil
      (/> chart coredns: badrepo\/coredns not found in repository https:\/\/bad-helm-repo.googleapis.com: No results found/ =~ result[:output]).should_not be_nil
      (/impacted: HelmChart\/coredns: badrepo\/coredns is not published in https:\/\/bad-helm-repo.googleapis.com/ =~ result[:output]).should_not be_nil
      verify_task_result("helm_chart_published", "failed")
    ensure
      result = ShellCmd.run("#{Helm::Binary.get} repo remove badrepo")
      result = ShellCmd.cnf_uninstall()
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
