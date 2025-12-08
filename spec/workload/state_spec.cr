require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/utils/mysql.cr"
require "file_utils"
require "sam"

describe "State" do
  before_all do
    result = ShellCmd.run_testsuite("setup:configuration_file_setup")
  end
  
  it "'elastic_volumes' should fail if the cnf does not use volumes that are elastic volume", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-elastic-volume/cnf-testsuite.yml", cmd_prefix: "LOG_LEVEL=debug")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "LOG_LEVEL=debug")
      (/(PASSED).*(All used volumes are elastic)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  #TODO This spec test should be for the skipped scenario instead.
  # This CNF does not use any volumes except the ones that Kubernetes might mount by default (like the service account token)
  it "'elastic_volumes' should fail if the cnf does not use any elastic volumes", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_nonroot", cmd_prefix: "LOG_LEVEL=debug")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "LOG_LEVEL=debug")
      (/FAILED/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'database_persistence' should pass if the cnf uses a database that uses an elastic volume with a stateful set", tags: ["elastic_volume"]  do
    begin
      Log.debug { "Installing Mysql " }
      # todo make helm directories work with parameters
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-mysql/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("database_persistence", cmd_prefix: "LOG_LEVEL=debug")
      (/(PASSED).*(CNF uses database with cloud-native persistence)/ =~ result[:output]).should_not be_nil
    ensure
      #todo fix cleanup for helm directory with parameters
      ShellCmd.cnf_uninstall()
      ShellCmd.run("kubectl delete pvc data-mysql-0", "delete_pvc")
    end
  end

  it "'elastic_volumes' should fail if the cnf doesn't use an elastic volume", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml", cmd_prefix: "LOG_LEVEL=debug")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "LOG_LEVEL=debug")
      (/(FAILED).*(Some of the used volumes are not elastic)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'no_local_volume_configuration' should fail if local storage configuration found", tags: ["no_local_volume_configuration"]  do
    begin
      # update the helm parameter with a schedulable node for the pv chart
      schedulable_nodes = KubectlClient::Get.schedulable_nodes_list
      schedulable_nodes.should_not be_empty

      update_yml("sample-cnfs/sample-local-storage/worker-node-value.yml", "worker_node", schedulable_nodes[0].dig("metadata", "name"))
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-local-storage/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("no_local_volume_configuration")
      (/(FAILED).*(local storage configuration volumes found)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      update_yml("sample-cnfs/sample-local-storage/worker-node-value.yml", "worker_node", "")
      result[:status].success?.should be_true
    end
  end

  it "'no_local_volume_configuration' should pass if local storage configuration is not found", tags: ["no_local_volume_configuration"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("no_local_volume_configuration")
      (/(PASSED).*(local storage configuration volumes not found)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
