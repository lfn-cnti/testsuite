require "./spec_helper"

describe "Free5gc certification" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
  end

  it "should successfully install and pass certification tests for Free5gc", tags: ["free5gc_cert"] do
    begin
      # Install Free5gc
      ShellCmd.cnf_install("--cnf-config ./example-cnfs/free5gc/cnti-testsuite.yaml --timeout 1800")

      # TEST mode would relax the production thresholds, so run without it.
      ENV.delete("CNTI_TESTSUITE_ENV")
      result = ShellCmd.run_testsuite("cert")

      # `cert` exits 0 when the CNF is certified and 1 when it is not; both are
      # acceptable here since this spec asserts the score, not the verdict.
      # Exit 2 (an errored test) means the suite itself broke and is not.
      result[:status].exit_code.should be < 2

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

describe "Free5gc workload" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
  end

  it "should run the full workload suite against Free5gc", tags: ["free5gc_workload"] do
    begin
      # Install Free5gc
      ShellCmd.cnf_install("--cnf-config ./example-cnfs/free5gc/cnti-testsuite.yaml --timeout 1800")

      ENV.delete("CNTI_TESTSUITE_ENV")
      result = ShellCmd.run_testsuite("workload")

      # `workload` exits 0 when every test passed and 1 when some failed; both
      # are acceptable here since this spec reports the score, not a verdict.
      # Exit 2 (an errored test) means the suite itself broke and is not.
      result[:status].exit_code.should be < 2

      result[:output].should match(/Workload: (PASSED|FAILED)/)
      result[:output].should match(/Final workload score: \d+ of \d+ points/)

    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
