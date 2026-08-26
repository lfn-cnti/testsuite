require "./../spec_helper"
require "../../src/tasks/**"
require "../../src/tasks/utils/cli_args_validation"

describe "CLI argument validation" do
  it "rejects unknown arguments with a usage error", tags: ["points"] do
    result = ShellCmd.run_testsuite("version bogus_flag")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("Unknown argument 'bogus_flag'")

    result = ShellCmd.run_testsuite("version bogus_key=1")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("Unknown argument 'bogus_key='")

    result = ShellCmd.run_testsuite("cnf_install --cnf-config whatever --timeout abc")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("not a number")

    # cnf-path was an undocumented alias of cnf-config; retired.
    result = ShellCmd.run_testsuite("cnf_install cnf-path=whatever")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("Unknown argument 'cnf-path='")
  end

  it "points a retired spelling at its replacement, and runs a second task named after the first", tags: ["points"] do
    result = ShellCmd.run_testsuite("all ~resilience")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("use `--skip resilience`")

    # A task name in an argument position is another task to run, in order.
    result = ShellCmd.run_testsuite("version test")
    result[:status].success?.should be_true
    result[:output].should contain("CNF TestSuite version:")
    result[:output].should contain("ping")
  end

  it "accepts GNU-style options and rejects unknown ones with a suggestion", tags: ["points"] do
    result = ShellCmd.run_testsuite("cnf_install --cnf-config /nonexistent/cnf-testsuite.yml")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("CNF configuration file not found")

    result = ShellCmd.run_testsuite("version --cnf-confg x")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("Did you mean '--cnf-config'?")

    result = ShellCmd.run_testsuite("version --timeout abc")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("not a number")
  end

  it "exits 64 when a task's own arguments are missing or name no file", tags: ["points"] do
    result = ShellCmd.run_testsuite("update_config")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("Usage: update_config")

    result = ShellCmd.run_testsuite("update_config --input-config /nonexistent.yml --output-config /tmp/ignored.yml")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("does not exist")

    result = ShellCmd.run_testsuite("validate_config")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("Usage: validate_config")

    result = ShellCmd.run_testsuite("validate_config --cnf-config /nonexistent/cnf-testsuite.yml")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("CNF configuration file not found")

    result = ShellCmd.run_testsuite("cnf_install --cnf-config /nonexistent/cnf-testsuite.yml")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("CNF configuration file not found")
  end

  it "exits 1, never 0, when a command refuses to do what was asked", tags: ["points"] do
    output_config = File.tempname("already-latest", ".yml")
    begin
      result = ShellCmd.run_testsuite("update_config --input-config spec/fixtures/cnf-testsuite-v2-example.yml --output-config #{output_config}")
      result[:status].exit_code.should eq(1)
      result[:output].should contain("already the latest version")
      File.exists?(output_config).should be_false
    ensure
      File.delete?(output_config)
    end
  end

  it "exits 2 when the suite itself breaks outside a test", tags: ["points"] do
    result = ShellCmd.run_testsuite("_raise_outside_task_runner")
    result[:status].exit_code.should eq(2)
    result[:output].should contain("unhandled")
  end

  it "invoked_task? matches only tasks named on the command line", tags: ["points"] do
    CLIParser.parse!(["state", "--cnf-config", "x", "--strict", "security"])
    invoked_task?("state").should be_true
    invoked_task?("security").should be_true
    invoked_task?("strict").should be_false   # option, not a task
    invoked_task?("x").should be_false

    # The old unanchored regexes matched substrings anywhere on the command
    # line - /ran/ matched an invocation of rolling_version_change.
    CLIParser.parse!(["rolling_version_change"])
    invoked_task?("ran").should be_false
    invoked_task?("rolling_version_change").should be_true
  end
end
