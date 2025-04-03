require "./../spec_helper"
require "colorize"
require "file_utils"
require "../../src/tasks/utils/utils.cr"

describe "Cluster API" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end
  after_each do
    result = ShellCmd.run_testsuite("setup:cluster_api_uninstall")
    result[:status].success?.should be_true
  end

  it "'clusterapi_enabled' should pass if cluster api is installed", tags: ["cluster-api"] do
    begin
      result = ShellCmd.run_testsuite("setup:cluster_api_install")
      current_dir = FileUtils.pwd 
      FileUtils.cd("#{current_dir}")
      result = ShellCmd.run_testsuite("clusterapi_enabled poc")
      (/Cluster API is enabled/ =~ result[:output]).should_not be_nil
    ensure
      Log.info { "Running Cleanup" }
      result = ShellCmd.run_testsuite("setup:cluster_api_uninstall") 
    end
  end
  
  it "'clusterapi_enabled' should fail if cluster api is not installed", tags: ["cluster-api-fail"] do
    begin
      result = ShellCmd.run_testsuite("clusterapi_enabled poc")
      (/Cluster API NOT enabled/ =~ result[:output]).should_not be_nil
    ensure
      Log.info { "Running Cleanup" }
      result = ShellCmd.run_testsuite("setup:cluster_api_uninstall")
    end
  end
end
