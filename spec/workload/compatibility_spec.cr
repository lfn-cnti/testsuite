require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/setup/kind_setup.cr"
require "file_utils"
require "sam"

describe "Compatibility" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end


  it "'cni_compatible' should pass when nothing couples the cnf to one CNI plugin", tags: ["compatibility"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("cni_compatible")
      result[:status].success?.should be_true
      (/(PASSED).*(No coupling to a specific CNI plugin detected)/ =~ result[:output]).should_not be_nil
      verify_task_result("cni_compatible", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'cni_compatible' should fail when the cnf requests CNI-specific features", tags: ["compatibility"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-cni-coupled/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("cni_compatible")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(CNF is coupled to specific CNI plugins or features)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/cni-coupled in cni-coupled: requests additional CNI networks: k8s.v1.cni.cncf.io\/networks/ =~ result[:output]).should_not be_nil
      verify_task_result("cni_compatible", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'increase_decrease_capacity' should say why a scale-up did not happen", tags: ["increase_decrease_capacity"] do
    begin
      # A ResourceQuota of one pod makes the cluster refuse the extra replicas;
      # the ReplicaSet's FailedCreate event is the cause and must be reported.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-capacity-quota/")
      result = ShellCmd.run_testsuite("increase_decrease_capacity")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Capacity change failed)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/capacity-quota in capacity-quota: could not scale up to 3 replicas \(1 ready\): / =~ result[:output]).should_not be_nil
      (/event ReplicaSet\/capacity-quota-[a-z0-9]+: FailedCreate: .*exceeded quota/ =~ result[:output]).should_not be_nil
      verify_task_result("increase_decrease_capacity", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'increase_decrease_capacity' should pass ", tags: ["increase_decrease_capacity"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnf-testsuite.yml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("increase_decrease_capacity")
      result[:status].success?.should be_true
      (/(PASSED).*(Replicas increased to)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall
    end
  end

  describe "deprecated_k8s_features", tags: ["deprecated_k8s_features"] do
    it "should pass if the CNF does not use any deprecated K8s features" do
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("deprecated_k8s_features")
      result[:status].success?.should be_true
      (/(PASSED).*(CNF does not use deprecated K8s features)/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall
    end

    it "should fail if the CNF uses any deprecated K8s features (no matter the installation type)" do
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-deprecated-k8s-v1.32/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("deprecated_k8s_features")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(CNF uses deprecated K8s features)/ =~ result[:output]).should_not be_nil
      (/annotation "kubernetes.io\/ingress.class" is deprecated/ =~ result[:output]).should_not be_nil
      (/metadata\.annotations\[kubernetes\.io\/enforce-mountable-secrets\]: deprecated in v1\.32\+/ =~
        result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall
    end

    it "should skip if the CNF installation log is not present" do
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-deprecated-k8s-v1.32/cnf-testsuite.yml")
      File.delete?(CNF_INSTALL_LOG_FILE).should be_true
      result = ShellCmd.run_testsuite("deprecated_k8s_features")
      result[:status].success?.should be_true
      (/(SKIPPED).*(CNF installation log file not found)/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
