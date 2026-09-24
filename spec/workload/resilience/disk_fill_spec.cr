require "../../spec_helper"
require "colorize"
require "../../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Resilience Disk Fill Chaos" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end


  it "'disk_fill' A 'Good' CNF should not crash when disk fill occurs", tags: ["disk_fill"]  do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("disk_fill")
      result[:status].success?.should be_true
      (/(PASSED).*(disk_fill chaos test passed)/ =~ result[:output]).should_not be_nil
      verify_task_result("disk_fill", "passed")
    rescue ex
      # Raise back error to ensure test fails.
      # The ensure block will uninstall the CNF and Litmus.
      raise "Test failed with #{ex.message}"
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("setup:uninstall_litmus")
      result[:status].success?.should be_true
    end
  end

  it "'disk_fill' passes without injecting when every container has a read-only root file system", tags: ["disk_fill"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-zombie-readonly-rootfs/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("disk_fill")
      result[:status].success?.should be_true
      (/(PASSED).*(disk_fill chaos test passed: every container has a read-only root file system)/ =~ result[:output]).should_not be_nil
      verify_task_result("disk_fill", "passed")

      yaml = YAML.parse(File.read(CNFManager::Points::Results.latest))
      item = yaml["items"].as_a.find { |i| i["name"].as_s == "disk_fill" }.not_nil!
      item["details"].as_a.map(&.as_s).any? { |d| d =~ /^Deployment\/zombie-readonly-rootfs in \S+: every container has a read-only root file system/ }.should be_true
      item["impacted_resources"]?.should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("setup:uninstall_litmus")
      result[:status].success?.should be_true
    end
  end

  it "'disk_fill' injects into the writable container when the first one is read-only", tags: ["disk_fill"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-mixed-rootfs/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("disk_fill")
      result[:status].success?.should be_true
      (/(PASSED).*(disk_fill chaos test passed)/ =~ result[:output]).should_not be_nil
      verify_task_result("disk_fill", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("setup:uninstall_litmus")
      result[:status].success?.should be_true
    end
  end

  it "'disk_fill' is not applicable to a bare Pod, which litmus cannot target", tags: ["disk_fill"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-immutable-fs/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("disk_fill")
      (/(N\/A).*(disk_fill not applicable: no Deployment, StatefulSet or DaemonSet for litmus to target)/ =~ result[:output]).should_not be_nil
      verify_task_result("disk_fill", "na")

      yaml = YAML.parse(File.read(CNFManager::Points::Results.latest))
      item = yaml["items"].as_a.find { |i| i["name"].as_s == "disk_fill" }.not_nil!
      item["details"].as_a.map(&.as_s).any?(&.starts_with?("Pod/nginx in cnfspace: litmus cannot target a Pod")).should be_true
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      result = ShellCmd.run_testsuite("setup:uninstall_litmus")
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
