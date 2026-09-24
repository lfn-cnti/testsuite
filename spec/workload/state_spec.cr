require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/utils/mysql.cr"
require "file_utils"
require "sam"

describe "State" do

  it "'elastic_volumes' should pass if all persistent volumes are elastic even when non-persistent volumes are present", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-elastic-volume/cnti-testsuite.yaml", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      (/(PASSED).*(All used volumes are elastic)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'elastic_volumes' should skip if the cnf does not use any persistent volumes", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_nonroot", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      (/(N\/A).*(No persistent volumes are used)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'database_persistence' should pass if the cnf uses a database that uses an elastic volume with a stateful set", tags: ["elastic_volume"]  do
    begin
      Log.debug { "Installing Mysql " }
      # todo make helm directories work with parameters
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-mysql/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("database_persistence", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      (/(PASSED).*(CNF uses database with cloud-native persistence)/ =~ result[:output]).should_not be_nil
    ensure
      #todo fix cleanup for helm directory with parameters
      ShellCmd.cnf_uninstall()
      ShellCmd.run("kubectl delete pvc data-mysql-0", "delete_pvc")
    end
  end

  it "'elastic_volumes' should skip if the cnf uses only non-persistent volumes", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      (/(N\/A).*(No persistent volumes are used)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'elastic_volumes' should pass if the cnf uses elastic persistent volumes", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-elastic-pvc/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      (/(PASSED).*(All used volumes are elastic)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'elastic_volumes' should pass for a statefulset with volumeClaimTemplates", tags: ["elastic_volume"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-elastic-vct/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      (/(PASSED).*(All used volumes are elastic)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'elastic_volumes' should fail if the cnf uses non-elastic persistent volumes", tags: ["elastic_volume"]  do
    with_sample_local_storage do
      result = ShellCmd.run_testsuite("elastic_volumes", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      (/(FAILED).*(Some of the used volumes are not elastic)/ =~ result[:output]).should_not be_nil
    end
  end

  it "'no_local_volume_configuration' should fail if local storage configuration found", tags: ["no_local_volume_configuration"]  do
    with_sample_local_storage do
      result = ShellCmd.run_testsuite("no_local_volume_configuration")
      (/(FAILED).*(local storage configuration volumes found)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/.* in .*: volume .* \(claim foo-pvc\) is bound to PersistentVolume example-pv with local path \/var\/tmp/ =~ result[:output]).should_not be_nil
    end
  end

  it "'no_local_volume_configuration' should not pass a claim that is bound to nothing", tags: ["no_local_volume_configuration"] do
    begin
      # A bare Pod (no spec.template, which used to raise into a rescue that
      # passed) whose claim can never bind: the storage type is unknown.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-unbound-claim --skip-wait-for-install")
      result = ShellCmd.run_testsuite("no_local_volume_configuration")
      (/(SKIPPED).*(1 persistent volume claim\(s\) not bound to a PersistentVolume)/ =~ result[:output]).should_not be_nil
      (/> Pod\/unbound-claim volume data: claim unbound-claim is not bound to a PersistentVolume/ =~ result[:output]).should_not be_nil
      verify_task_result("no_local_volume_configuration", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'no_local_volume_configuration' should pass if local storage configuration is not found", tags: ["no_local_volume_configuration"]  do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
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

private def with_sample_local_storage(&)
  schedulable_nodes = KubectlClient::Get.schedulable_nodes_list
  schedulable_nodes.should_not be_empty
  update_yml("sample-cnfs/sample-local-storage/worker-node-value.yml", "worker_node", schedulable_nodes[0].dig("metadata", "name"))
  begin
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-local-storage/cnti-testsuite.yaml")
    yield
  ensure
    result = ShellCmd.cnf_uninstall()
    update_yml("sample-cnfs/sample-local-storage/worker-node-value.yml", "worker_node", "")
    result[:status].success?.should be_true
  end
end
