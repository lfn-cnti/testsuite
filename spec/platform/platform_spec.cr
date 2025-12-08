require "./../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"

describe "Platform" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "'platform:*' should not error out when no cnf is installed", tags: ["platform"] do
    result = ShellCmd.run_testsuite("platform:oci_compliant")
    puts result[:output]
    (/No cnf_testsuite.yml found/ =~ result[:output]).should be_nil
  end
  it "'platform' should not run prerequisites that are prefixed with a ~", tags: ["platform"] do
    result = ShellCmd.run_testsuite("platform ~k8s_conformance")
    (/kind=namespace namespace=sonobuoy/ =~ (result[:output] + result[:error])).should be_nil
  end
  it "'k8s_conformance' should pass if the sonobuoy tests pass", tags: ["platform"] do
    result = ShellCmd.run_testsuite("k8s_conformance")
    (/(PASSED).*(K8s conformance test has no failures)/ =~ result[:output]).should_not be_nil
  end
  
  it "individual tasks like 'platform:control_plane_hardening' should not require an installed cnf to run", tags: ["platform"] do
    result = ShellCmd.run_testsuite("platform:control_plane_hardening")
    (/You must install a CNF first./ =~ result[:output]).should be_nil
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end

