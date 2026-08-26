require "./../spec_helper"
require "colorize"
require "./../../src/tasks/utils/utils.cr"

describe "Platform" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end
  it "'worker_reboot_recovery' should pass if platform successfully recovers after reboot", tags: ["platform:worker_reboot_recovery"] do
    if check_destructive
      puts "Tests running in destructive mode".colorize(:red)
      result = ShellCmd.run_testsuite("platform:worker_reboot_recovery --destructive")
      (/(PASSED).*(Node came back online)/ =~ result[:output]).should_not be_nil
    else
      result = ShellCmd.run_testsuite("platform:worker_reboot_recovery")
      (/SKIPPED/ =~ result[:output]).should_not be_nil
    end
  end
end

