require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

def verify_task_result(task_name : String, expected_status : String)
  latest_results = Dir.glob("results/cnf-testsuite-results-*.yml").max_by { |path| File.info(path).modification_time }
  latest_results.should_not be_nil
  yaml = YAML.parse(File.read(latest_results.not_nil!))
  item = yaml["items"].as_a.find { |i| i["name"].as_s == task_name }
  item.should_not be_nil
  item.not_nil!["status"].as_s.should eq(expected_status)
end

describe "Resilience pod memory hog Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result = ShellCmd.run_testsuite("setup:configuration_file_setup")
    result[:status].success?.should be_true
  end


  it "'pod_memory_hog' A 'Good' CNF should not crash when pod memory hog occurs", tags: ["pod_memory_hog"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("pod_memory_hog")
      result[:status].success?.should be_true
      (/(PASSED).*(pod_memory_hog chaos test passed)/ =~ result[:output]).should_not be_nil
      verify_task_result("pod_memory_hog", "passed")
    rescue ex
      # Raise back error to ensure test fails.
      # The ensure block will uninstall the CNF and Litmus.
      raise "Test failed with #{ex.message}"
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("uninstall_litmus")
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
