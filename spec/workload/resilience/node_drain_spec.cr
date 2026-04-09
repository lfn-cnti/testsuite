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

describe "Resilience Node Drain Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result = ShellCmd.run_testsuite("setup:configuration_file_setup")
    result[:status].success?.should be_true
  end


  it "'node_drain' A 'Good' CNF should not crash when node drain occurs", tags: ["node_drain"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("node_drain")
      result[:status].success?.should be_true
      if KubectlClient::Get.schedulable_nodes_list.size > 1
        (/(PASSED).*(node_drain chaos test passed)/ =~ result[:output]).should_not be_nil
        verify_task_result("node_drain", "passed")
      else
        (/(SKIPPED).*(node_drain chaos test requires the cluster to have atleast two)/ =~ result[:output]).should_not be_nil
        verify_task_result("node_drain", "skipped")
      end
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
