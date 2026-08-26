require "../spec_helper"
require "../../src/tasks/utils/utils.cr"
require "colorize"

describe CnfTestSuite do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "a task should fail with an exit code of 2 when there is an exception", tags: ["security"] do
    begin
      result = ShellCmd.run_testsuite("_divide_by_zero --strict")
      (result[:status].exit_code == 2).should be_true
    end
  end
end
