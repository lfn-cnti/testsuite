require "./../spec_helper"
require "../../src/tasks/utils/sam_args_patch"
require "../../src/tasks/utils/cli_args_validation"

describe "CLI argument validation" do
  it "rejects unknown flags and named arguments with a usage error", tags: ["points"] do
    result = ShellCmd.run_testsuite("version bogus_flag")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("Unknown flag 'bogus_flag'")

    result = ShellCmd.run_testsuite("version bogus_key=1")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("Unknown argument 'bogus_key='")

    result = ShellCmd.run_testsuite("cnf_install cnf-config=whatever timeout=abc")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("not a number")
  end

  it "warns on unmatched exclusions and task names in argument positions", tags: ["points"] do
    result = ShellCmd.run_testsuite("version ~no_such_task")
    result[:status].success?.should be_true
    result[:output].should contain("does not match any task")

    result = ShellCmd.run_testsuite("version delete_results")
    result[:status].success?.should be_true
    result[:output].should contain("separate them with")
  end

  it "preserves '=' characters inside named argument values", tags: ["points"] do
    Sam::Args.new(["cnf-config=a=b"]).named["cnf-config"].should eq("a=b")
  end

  it "invoked_task? matches only tokens in task positions", tags: ["points"] do
    original = ARGV.dup
    begin
      ARGV.clear
      ARGV.concat(["state", "cnf-config=x", "strict", "@", "security"])
      invoked_task?("state").should be_true
      invoked_task?("security").should be_true      # after the '@' separator
      invoked_task?("strict").should be_false       # flag, not a task position
      invoked_task?("cnf-config=x").should be_false

      # The old unanchored regexes matched substrings anywhere on the command
      # line - /ran/ matched an invocation of rolling_version_change.
      ARGV.clear
      ARGV.concat(["rolling_version_change"])
      invoked_task?("ran").should be_false
      invoked_task?("rolling_version_change").should be_true
    ensure
      ARGV.clear
      ARGV.concat(original)
    end
  end
end
