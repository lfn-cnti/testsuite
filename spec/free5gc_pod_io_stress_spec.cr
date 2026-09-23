require "./spec_helper"

describe "Free5gc pod_io_stress" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
  end

  it "should install Free5gc and pass pod_io_stress", tags: ["free5gc_pod_io_stress"] do
    passed = false
    begin
      # Install Free5gc
      ShellCmd.cnf_install("--cnf-config ./example-cnfs/free5gc/cnti-testsuite.yaml --timeout 1800")

      # TEST mode would relax the production thresholds, so run without it.
      ENV.delete("CNTI_TESTSUITE_ENV")
      result = ShellCmd.run_testsuite("pod_io_stress")

      passed = result[:status].success?
      result[:status].success?.should be_true
      result[:output].should match(/PASSED/)
      verify_task_result("pod_io_stress", "passed")
    ensure
      # On failure keep the cluster intact so the workflow can collect the
      # retained litmus pods and events.
      result = ShellCmd.cnf_uninstall() if passed
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end