require "./../spec_helper"
require "../../src/tasks/utils/sam_args_patch"

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
end
