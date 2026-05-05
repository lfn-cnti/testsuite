require "./spec_helper"

describe "Free5gc certification" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
  end

  it "should successfully install and pass certification tests for Free5gc", tags: ["free5gc"] do
    begin
      # Install Free5gc
      ShellCmd.cnf_install("cnf-config=./example-cnfs/free5gc/cnf-testsuite.yml timeout=1800")
      
      # Run the cert suite
      cert_args = %(cert exclude="node_drain non_root_containers")
      result = ShellCmd.run_testsuite(cert_args)
      
      # Ensure the testsuite binary didn't crash
      result[:status].success?.should be_true
      
      result[:output].should match(/PASSED/)
      result[:output].should match(/17 of 19 total tests passed/)
      
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
