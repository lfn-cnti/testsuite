require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/setup/kind_setup.cr"
require "file_utils"
require "sam"

describe "Core" do

  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true 
  end

  it "'smf_upf_heartbeat' should pass if the smf_upf core is resilient to network latency", tags: ["core"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample_open5gs/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("smf_upf_heartbeat")
      (/(PASSED).*(Chaos service degradation is less than 50%)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'smf_upf_heartbeat' should fail if the smf_upf core is not resilient to network latency", tags: ["core"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample_open5gs/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("smf_upf_heartbeat baseline_count=300")
      (/(FAILED).*(Chaos service degradation is more than 50%)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'suci_enabled' should pass if the 5G core has suci enabled", tags: ["5g"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample_open5gs/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("suci_enabled")
      (/(PASSED).*(Core uses SUCI 5g authentication)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'suci_enabled' should fail if the 5G core does not have suci enabled", tags: ["5g"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample_open5gs_no_auth/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("suci_enabled")
      (/(FAILED).*(Core does not use SUCI 5g authentication)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

end
