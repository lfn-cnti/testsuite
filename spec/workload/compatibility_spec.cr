require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Compatibility" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end


  it "'cni_compatible' should pass when nothing couples the cnf to one CNI plugin", tags: ["compatibility"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
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
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-cni-coupled/cnti-testsuite.yaml")
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
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("increase_decrease_capacity")
      result[:status].success?.should be_true
      (/(PASSED).*(Replicas increased to)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall
    end
  end

  describe "deprecated_k8s_features", tags: ["deprecated_k8s_features"] do
    it "should pass if the CNF does not use any deprecated K8s features" do
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("deprecated_k8s_features")
      result[:status].success?.should be_true
      (/(PASSED).*(CNF does not use deprecated K8s features)/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall
    end

    it "should fail if the CNF uses any deprecated K8s features (no matter the installation type)" do
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-deprecated-k8s-v1.32/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("deprecated_k8s_features")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(CNF uses deprecated K8s features)/ =~ result[:output]).should_not be_nil
      (/annotation "kubernetes.io\/ingress.class" is deprecated/ =~ result[:output]).should_not be_nil
      (/metadata\.annotations\[kubernetes\.io\/enforce-mountable-secrets\]: deprecated in v1\.32\+/ =~
        result[:output]).should_not be_nil
      # Each warning is attributed to the resource that carries it.
      (/impacted: ServiceAccount\/deprecated-sa in cnti-default: metadata\.annotations\[kubernetes\.io\/enforce-mountable-secrets\]/ =~ result[:output]).should_not be_nil
      (/impacted: Ingress\/deprecated-ingress in .*: annotation "kubernetes.io\/ingress.class" is deprecated/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall
    end

    it "should not depend on the installation log" do
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-deprecated-k8s-v1.32/cnti-testsuite.yaml")
      File.delete?(CNF_INSTALL_LOG_FILE).should be_true
      result = ShellCmd.run_testsuite("deprecated_k8s_features")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(CNF uses deprecated K8s features)/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall
    end

    it "should skip if the CNF manifest is not present" do
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-deprecated-k8s-v1.32/cnti-testsuite.yaml")
      File.delete?(COMMON_MANIFEST_FILE_PATH).should be_true
      result = ShellCmd.run_testsuite("deprecated_k8s_features")
      result[:status].success?.should be_true
      (/(SKIPPED).*(CNF manifest not found)/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall
    end
  end

  it "'dual_stack' should pass when every Service declares dual-stack", tags: ["dual_stack"] do
    begin
      # dual_stack only inspects Services, so the pods need not be Ready.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_dual_stack/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("dual_stack")
      result[:status].success?.should be_true
      (/(PASSED).*(All Services declare dual-stack)/ =~ result[:output]).should_not be_nil
      verify_task_result("dual_stack", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'dual_stack' should fail when a Service does not declare dual-stack", tags: ["dual_stack"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_dual_stack_fail/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("dual_stack")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(do not declare dual-stack)/ =~ result[:output]).should_not be_nil
      # The finding names the actual policy and its consequence on a dual-stack cluster.
      (/impacted: Service\/single-stack-app.*on a dual-stack cluster this Service receives only/ =~ result[:output]).should_not be_nil
      verify_task_result("dual_stack", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'dual_stack' should be skipped when none of the CNF's Services is in the cluster", tags: ["dual_stack"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_dual_stack/cnti-testsuite.yaml --skip-wait-for-install")
      # The manifest still declares the Service, but the cluster no longer has it.
      KubectlClient::Delete.resource("service", "dual-stack-app", CLUSTER_DEFAULT_NAMESPACE)
      result = ShellCmd.run_testsuite("dual_stack")
      (/(SKIPPED).*(None of the CNF's Services were found in the cluster)/ =~ result[:output]).should_not be_nil
      verify_task_result("dual_stack", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'dual_stack' should be N/A when the CNF exposes no Service", tags: ["dual_stack"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_dual_stack_no_service/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("dual_stack")
      result[:status].success?.should be_true
      (/(N\/A).*(dual-stack declaration does not apply)/ =~ result[:output]).should_not be_nil
      verify_task_result("dual_stack", "na")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
