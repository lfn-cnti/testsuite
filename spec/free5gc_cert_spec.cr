require "./spec_helper"

describe "Free5gc certification" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
  end

  it "should successfully install and pass certification tests for Free5gc", tags: ["free5gc"] do
    begin
      # Install Free5gc
      ShellCmd.cnf_install("cnf-config=./example-cnfs/free5gc/cnf-testsuite.yml timeout=1800")
      
      result = ShellCmd.run_testsuite("cert")
      
      #check test result
      puts "\n=== TESTSUITE OUTPUT ===\n#{result[:output]}\n========================\n"

      # Ensure the testsuite binary didn't crash
      result[:status].success?.should be_true
      
      result[:output].should match(/PASSED/)
      result[:output].should match(/(17|18|19) of 19 total tests passed/)
      
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
