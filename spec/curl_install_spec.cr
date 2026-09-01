# coding: utf-8
require "./spec_helper"
require "colorize"
require "../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "CurlInstall" do
  after_all do
    Log.info { "Curl install tests finished.  Building ./cnti-testsuite again".colorize(:green) }
    result = ShellCmd.run("crystal build src/cnti-testsuite.cr")
    if result[:status].success?
      Log.info { "Build Success!".colorize(:green) }
    else
      Log.info { "crystal build failed!".colorize(:red) }
      raise "crystal build failed! curl_install_spec.cr"
    end
  end
  it "'source curl_install.sh' should download a cnti-testsuite binary", tags: ["curl"]  do
    result = ShellCmd.run("/bin/bash -c 'source ./curl_install.sh'", force_output: true)
    result[:status].success?.should be_true
    (/cnti-testsuite/ =~ result[:output]).should_not be_nil
  end
  it "'curl_install.sh' should download a cnti-testsuite binary", tags: ["curl"]  do
    result = ShellCmd.run("./curl_install.sh", force_output: true)
    result[:status].success?.should be_true
    (/To use the cnti-testsuite please restart you terminal session to load the new PATH/ =~ result[:output]).should_not be_nil
  end
end
