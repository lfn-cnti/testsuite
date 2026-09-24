require "./spec_helper"

# Shared body of the example CNF validation specs (free5GC, OCUDU, ...): each
# spec file only names its CNF and carries the literal `<cnf>_cert` and
# `<cnf>_workload` tags that CI selects and keeps out of the PR matrix.
module ExampleCNFValidation
  # The spec helper turns TEST mode on for the local specs; it relaxes the
  # production thresholds, so the validation runs go without it.
  PRODUCTION_ENV = "env -u CNTI_TESTSUITE_ENV"

  # Installs the CNF, runs the cert suite and requires the CNF to be certified.
  def self.cert(config : String)
    ShellCmd.cnf_install("--cnf-config #{config} --timeout 1800")
    result = ShellCmd.run_testsuite("cert", cmd_prefix: PRODUCTION_ENV)

    # `cert` exits 0 when the CNF is certified and 1 when it is not. Exit 2
    # (an errored test) means the suite itself broke.
    result[:status].exit_code.should be < 2

    # The verdict line, not a hard-coded test count: the essential set can
    # change size without the CNF losing its certification.
    result[:output].should match(/^Cert: PASSED \(\d+ of \d+ essential tests passed, threshold \d+\)/m)
  ensure
    ShellCmd.cnf_uninstall()
  end

  # Installs the CNF and runs the whole workload suite: the score is reported,
  # failed tests are acceptable, an errored test is not.
  def self.workload(config : String)
    ShellCmd.cnf_install("--cnf-config #{config} --timeout 1800")
    result = ShellCmd.run_testsuite("workload", cmd_prefix: PRODUCTION_ENV)

    # `workload` exits 0 when every test passed and 1 when some failed. Exit 2
    # (an errored test) means the suite itself broke.
    result[:status].exit_code.should be < 2

    result[:output].should match(/^Workload: (PASSED|FAILED)/m)
    result[:output].should match(/^Final workload score: \d+ of \d+ points/m)
  ensure
    ShellCmd.cnf_uninstall()
  end
end
