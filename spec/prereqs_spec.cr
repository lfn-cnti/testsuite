require "./spec_helper"
require "colorize"
require "../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Prereq" do
  it "'prereq' should check the system for prerequisites", tags: ["points"]  do
    result = ShellCmd.run_testsuite("setup:prereqs")
    result[:status].success?.should be_true
    (/helm found/ =~ result[:output]).should_not be_nil

    (/kubectl found/ =~ result[:output]).should_not be_nil
    (/git found/ =~ result[:output]).should_not be_nil
  end
end
