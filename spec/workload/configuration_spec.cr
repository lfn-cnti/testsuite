require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"

describe CntiTestSuite do
  before_all do
    result = ShellCmd.run("pwd")
    Log.debug { result[:output] }
    result = ShellCmd.run("echo $KUBECONFIG")
    Log.debug { result[:output] }

    result = ShellCmd.run_testsuite("setup")
    result = ShellCmd.run_testsuite("setup:create_namespace")
  end


  it "'liveness' should pass when livenessProbe is set", tags: ["liveness"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/k8s-multiple-deployments/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("liveness", cmd_prefix:"CNTI_TESTSUITE_LOG_LEVEL=debug")
      result[:status].success?.should be_true
      (/(PASSED).*(All workload resources have at least one container with a liveness probe)/ =~ result[:output]).should_not be_nil
      (/> Deployment\/.* in .*: liveness probe on .+/ =~ result[:output]).should_not be_nil
      verify_task_result("liveness", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'liveness' lists a Job and a CronJob as not applicable and judges the rest", tags: ["liveness"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-batch-workloads/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("liveness")
      result[:status].success?.should be_true
      (/(PASSED).*(All workload resources have at least one container with a liveness probe)/ =~ result[:output]).should_not be_nil
      (/> Deployment\/batch-web in batch-workloads: liveness probe on web/ =~ result[:output]).should_not be_nil
      (/> Job\/batch-once in batch-workloads: a Job runs to completion, liveness is not applicable to it/ =~ result[:output]).should_not be_nil
      (/> CronJob\/batch-nightly in batch-workloads: a CronJob runs to completion, liveness is not applicable to it/ =~ result[:output]).should_not be_nil
      verify_task_result("liveness", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'liveness' should fail when livenessProbe is not set", tags: ["liveness"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns_bad_liveness/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("liveness")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(One or more workload resources have no containers with a liveness probe)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/.* in .*: no liveness probe on any container \(.+\)/ =~ result[:output]).should_not be_nil
      verify_task_result("liveness", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  # docs/MCP.md shows an agent fixing these two failures in the demo CNF, so the
  # demo has to keep failing as shipped and pass with the probes the guide sets.
  it "the MCP guide's demo CNF fails liveness and readiness, and passes with the guide's probes", tags: ["liveness"] do
    demo = "./sample-cnfs/sample-mcp-demo"
    begin
      ShellCmd.cnf_install("--cnf-config #{demo}/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("liveness readiness")
      (/impacted: Deployment\/.*-web in .*: no liveness probe on any container \(web\)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/.*-web in .*: no readiness probe on any container \(web\)/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall()
    end

    probes = %w(livenessProbe readinessProbe).flat_map do |probe|
      ["--set #{probe}.httpGet.path=/", "--set #{probe}.httpGet.port=http"]
    end
    # Next to the demo, so its chart path resolves as in the demo's own config.
    fixed = "#{demo}/cnti-testsuite-fixed-#{Random::Secure.hex(4)}.yaml"
    File.write(fixed, <<-YAML)
      config_version: v2
      deployments:
        helm_dirs:
          - name: web
            helm_directory: chart
            helm_values: "#{probes.join(" ")}"
      YAML
    begin
      ShellCmd.cnf_install("--cnf-config #{fixed}")
      result = ShellCmd.run_testsuite("liveness readiness")
      result[:status].success?.should be_true
      (/(PASSED).*(All workload resources have at least one container with a liveness probe)/ =~ result[:output]).should_not be_nil
      (/(PASSED).*(All workload resources have at least one container with a readiness probe)/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall()
      File.delete(fixed) if File.exists?(fixed)
    end
  end

  it "'readiness' should pass when readinessProbe is set", tags: ["readiness"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/k8s-multiple-deployments/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("readiness", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=debug")
      result[:status].success?.should be_true
      (/(PASSED).*(All workload resources have at least one container with a readiness probe)/ =~ result[:output]).should_not be_nil
      verify_task_result("readiness", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'readiness' should fail when readinessProbe is not set", tags: ["readiness"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns_bad_liveness/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("readiness")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(One or more workload resources have no containers with a readiness probe)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/.* in .*: no readiness probe on any container \(.+\)/ =~ result[:output]).should_not be_nil
      verify_task_result("readiness", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'pod_owner' should pass when every pod is owned by a controller", tags: ["pod_owner"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_pod_owner/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("pod_owner")
      result[:status].success?.should be_true
      (/(PASSED).*(All 1 pod\(s\) of the CNF are owned by a controller)/ =~ result[:output]).should_not be_nil
      verify_task_result("pod_owner", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'pod_owner' should fail on a bare Pod declared in the manifest", tags: ["pod_owner"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-hostport-pod/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("pod_owner")
      result[:status].exit_code.should eq(1)
      (/impacted: Pod\/hostport-pod in hostport-pod: declared as a bare Pod in the CNF's manifest/ =~ result[:output]).should_not be_nil
      verify_task_result("pod_owner", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'pod_owner' should report a bare Pod once when a Deployment's selector also matches it", tags: ["pod_owner"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_pod_owner_mixed/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("pod_owner")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Found 1 of 2 pod\(s\) of the CNF not owned by a controller)/ =~ result[:output]).should_not be_nil
      result[:output].scan(/impacted: Pod\/pod-owner-mixed-bare/).size.should eq(1)
      (/impacted: Pod\/pod-owner-mixed-bare in .*: declared as a bare Pod in the CNF's manifest/ =~ result[:output]).should_not be_nil
      verify_task_result("pod_owner", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'pod_owner' should not count a Helm hook Pod that carries the workload's labels", tags: ["pod_owner"] do
    # What a chart leaves behind after `helm test`: a hook Pod with the
    # Deployment's labels, created after the install.
    hook = "pod-owner-hook.yml"
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_pod_owner/cnti-testsuite.yaml")
      File.write(hook, <<-YAML)
        apiVersion: v1
        kind: Pod
        metadata:
          name: pod-owner-app-test-connection
          namespace: #{CLUSTER_DEFAULT_NAMESPACE}
          labels:
            app: pod-owner-app
          annotations:
            helm.sh/hook: test
        spec:
          restartPolicy: Never
          containers:
          - name: test
            image: busybox:1.36
            command: ["sh", "-c", "true"]
            securityContext:
              allowPrivilegeEscalation: false
              runAsNonRoot: true
              runAsUser: 1000
              capabilities:
                drop: ["ALL"]
              seccompProfile:
                type: RuntimeDefault
        YAML
      KubectlClient::Apply.file(hook)
      result = ShellCmd.run_testsuite("pod_owner")
      result[:status].success?.should be_true
      (/(PASSED).*(All 1 pod\(s\) of the CNF are owned by a controller)/ =~ result[:output]).should_not be_nil
      verify_task_result("pod_owner", "passed")
    ensure
      KubectlClient::Delete.file(hook) rescue nil
      File.delete?(hook)
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'pod_owner' should be skipped when the CNF has no pod", tags: ["pod_owner"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_pod_owner_no_pods/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("pod_owner")
      (/(SKIPPED).*(No pod of the CNF could be read)/ =~ result[:output]).should_not be_nil
      verify_task_result("pod_owner", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'disruption_budget' should pass when replicas are spread and a budget allows an eviction", tags: ["disruption_budget"] do
    begin
      # The test reads the manifest and the live budgets, not the pods: a
      # required anti-affinity leaves a second replica Pending on one node.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_disruption_budget/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("disruption_budget")
      result[:status].success?.should be_true
      (/(PASSED).*(Every replicated workload is covered by a disruption budget)/ =~ result[:output]).should_not be_nil
      (/PodDisruptionBudget\/disruption-budget-app in .*: allows 1 of 2 selected pod\(s\)/ =~ result[:output]).should_not be_nil
      verify_task_result("disruption_budget", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'disruption_budget' should fail when a replicated workload has no budget", tags: ["disruption_budget"] do
    begin
      # The test reads the manifest and the live budgets, not the pods: a
      # required anti-affinity leaves a second replica Pending on one node.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_disruption_budget_none/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("disruption_budget")
      result[:status].exit_code.should eq(1)
      (/impacted: Deployment\/disruption-budget-none in .*: 2 replicas, but no PodDisruptionBudget selects its pods/ =~ result[:output]).should_not be_nil
      verify_task_result("disruption_budget", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'disruption_budget' should fail on a budget that allows no eviction", tags: ["disruption_budget"] do
    begin
      # The test reads the manifest and the live budgets, not the pods: a
      # required anti-affinity leaves a second replica Pending on one node.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_disruption_budget_blocking/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("disruption_budget")
      result[:status].exit_code.should eq(1)
      (/impacted: PodDisruptionBudget\/disruption-budget-blocking in .*: allows no eviction of its 2 selected pod\(s\) \(maxUnavailable: 0\)/ =~ result[:output]).should_not be_nil
      verify_task_result("disruption_budget", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'disruption_budget' should fail on a workload that two budgets select", tags: ["disruption_budget"] do
    begin
      # The test reads the manifest and the live budgets, not the pods: a
      # required anti-affinity leaves a second replica Pending on one node.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_disruption_budget_overlap/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("disruption_budget")
      result[:status].exit_code.should eq(1)
      (/impacted: Deployment\/disruption-budget-overlap in .*: selected by PodDisruptionBudget\/disruption-budget-overlap and PodDisruptionBudget\/disruption-budget-overlap-tier; the eviction API refuses pods with more than one budget/ =~ result[:output]).should_not be_nil
      verify_task_result("disruption_budget", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'disruption_budget' should be N/A for a single replica without a budget", tags: ["disruption_budget"] do
    begin
      # The test reads the manifest and the live budgets, not the pods: a
      # required anti-affinity leaves a second replica Pending on one node.
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_disruption_budget_single/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("disruption_budget")
      (/(N\/A).*(no workload with more than one replica and no PodDisruptionBudget)/ =~ result[:output]).should_not be_nil
      verify_task_result("disruption_budget", "na")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'rolling_update' should pass when valid version is given", tags: ["rolling_update"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_update")
      result[:status].success?.should be_true
      (/Passed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_update' should fail when invalid version is given", tags: ["rolling_update"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_invalid_version/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_update")
      result[:status].exit_code.should eq(1)
      (/Failed/ =~ result[:output]).should_not be_nil
      # A rollout that does not complete names the resource, the image and why.
      (/impacted: Deployment\/.* in .* \(container .+\): rollout to .*:.* did not complete within 200s/ =~ result[:output]).should_not be_nil
      # Why, from the pods: the image does not exist, so it cannot be pulled.
      (/did not complete within 200s.*(ErrImagePull|ImagePullBackOff)/ =~ result[:output]).should_not be_nil
      # And the test put the deployed image back, so the tests after it start
      # from the CNF as deployed.
      deployment = KubectlClient::Get.resource("deployment", "coredns-coredns", DEFAULT_CNF_NAMESPACE)
      image = deployment.dig("spec", "template", "spec", "containers", 0, "image").as_s
      image.includes?("this_is_not_a_valid_version").should be_false
      deployment.dig?("status", "readyReplicas").try(&.as_i).should eq(deployment.dig("spec", "replicas").as_i)
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_update' should roll to the image's previous release when no test tag is configured", tags: ["rolling_update"] do
    begin
      # A chart directory (no previous release to install), and no container_names:
      # the image path, with the image's previous release from its registry.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_update")
      result[:status].success?.should be_true
      (/container coredns: no rolling_update_test_tag configured, using \S+, the release before the deployed \S+/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_update' should roll the operator's Deployment and leave the Deployment the operator owns alone", tags: ["rolling_update"] do
    begin
      install = ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-operator-owned-rolling/cnti-testsuite.yaml")
      (/Added 1 resources via ownerReferences to composite manifest/ =~ install[:output]).should_not be_nil
      result = ShellCmd.run_testsuite("rolling_update")
      result[:status].success?.should be_true
      (/Deployment\/demo-owned in cnti-default: image set by PodSet\/demo-owned, not rolled; upgrade it through the custom resource/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "passed")
      # The owned Deployment still runs what its PodSet says.
      image = KubectlClient::Get.resource("deployment", "demo-owned", DEFAULT_CNF_NAMESPACE).dig("spec", "template", "spec", "containers", 0, "image").as_s
      image.should eq("nginx")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_update' and 'rollback' should be N/A when every workload of the CNF is owned by an operator", tags: ["rolling_update"] do
    begin
      # The operator lives outside the CNF, installed beforehand.
      ShellCmd.run("kubectl create namespace #{DEFAULT_CNF_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -", force_output: true)
      ShellCmd.run("kubectl label namespace #{DEFAULT_CNF_NAMESPACE} pod-security.kubernetes.io/enforce=privileged --overwrite", force_output: true)
      Helm.install("podset-operator", "sample-cnfs/sample-operator/simple_pod_operator", namespace: DEFAULT_CNF_NAMESPACE)
      KubectlClient::Wait.resource_wait_for_install("deployment", "podset-operator", namespace: DEFAULT_CNF_NAMESPACE).should be_true
      install = ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-operator-owned-only/cnti-testsuite.yaml")
      (/Added 1 resources via ownerReferences to composite manifest/ =~ install[:output]).should_not be_nil
      result = ShellCmd.run_testsuite("rolling_update")
      (/N\/A.*Every workload of the CNF takes its image from an operator's custom resource, a rolling update does not apply/ =~ result[:output]).should_not be_nil
      (/Deployment\/demo-owned in cnti-default: image set by PodSet\/demo-owned, not rolled/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "na")
      result = ShellCmd.run_testsuite("rollback")
      (/N\/A.*Every workload of the CNF takes its image from an operator's custom resource, a rollback does not apply/ =~ result[:output]).should_not be_nil
      verify_task_result("rollback", "na")
    ensure
      result = ShellCmd.cnf_uninstall()
      # The namespace stays: the next spec installs into it, and a namespace
      # being terminated refuses that.
      Helm.uninstall("podset-operator", DEFAULT_CNF_NAMESPACE)
    end
  end

  it "'rolling_update' should skip with remediation when no tag is configured and the deployed tag names no version", tags: ["rolling_update"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_moving_tag --skip-wait-for-install")
      result = ShellCmd.run_testsuite("rolling_update")
      (/(SKIPPED).*(No usable rolling_update_test_tag configured for any container, and no previous release to take from the registry)/ =~ result[:output]).should_not be_nil
      (/remediation: No rolling_update_test_tag configured for container app, and its tag stable names no version/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_update' should skip, not pass, when the test tag is the deployed tag", tags: ["rolling_update"] do
    begin
      # The sample_rolling chart deploys coredns 1.6.7; the test tag is 1.6.7 too.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_deployed_tag/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_update")
      (/(SKIPPED).*(No usable rolling_update_test_tag configured for any container)/ =~ result[:output]).should_not be_nil
      (/remediation: rolling_update_test_tag 1.6.7 for container coredns is the deployed tag, so nothing would roll out/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_downgrade' should pass when valid version is given", tags: ["rolling_downgrade"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("rolling_downgrade")
      result[:status].success?.should be_true
      (/Passed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_downgrade' should fail when invalid version is given", tags: ["rolling_downgrade"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_invalid_version/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_downgrade")
      result[:status].exit_code.should eq(1)
      (/Failed/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/coredns-coredns in .* \(container coredns\): rollout to .*coredns:this_is_not_a_valid_version did not complete/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_downgrade", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_version_change' should pass when valid version is given", tags: ["rolling_version_change"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("rolling_version_change")
      result[:status].success?.should be_true
      (/Passed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_version_change' should fail when invalid version is given", tags: ["rolling_version_change"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_invalid_version/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_version_change")
      result[:status].exit_code.should eq(1)
      (/Failed/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/coredns-coredns in .* \(container coredns\): rollout to .*coredns:this_is_not_a_valid_version did not complete/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_version_change", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rollback' should pass ", tags: ["rollback"]  do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("rollback")
      result[:status].success?.should be_true
      (/Passed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rollback' should roll back from the image's previous release when no rollback_from_tag is configured", tags: ["rollback"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rollback")
      result[:status].success?.should be_true
      (/container coredns: no rollback_from_tag configured, using \S+, the release before the deployed \S+/ =~ result[:output]).should_not be_nil
      verify_task_result("rollback", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rollback' should skip with remediation when no rollback_from_tag is configured and the deployed tag names no version", tags: ["rollback"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_moving_tag --skip-wait-for-install")
      result = ShellCmd.run_testsuite("rollback")
      (/(SKIPPED).*(No usable rollback_from_tag configured for any container, and no previous release to take from the registry)/ =~ result[:output]).should_not be_nil
      (/remediation: No rollback_from_tag configured for container app, and its tag stable names no version/ =~ result[:output]).should_not be_nil
      verify_task_result("rollback", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rollback' should fail with the reason when the rollout cannot be undone (revisionHistoryLimit 0)", tags: ["rollback"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_no_history/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rollback")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(CNF Rollback Failed)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/no-history in no-history \(container app\): rollout undo failed: no rollout history found/ =~ result[:output]).should_not be_nil
      (/remediation: Deployment\/no-history keeps no revision to roll back to: set spec\.revisionHistoryLimit to 1 or more/ =~ result[:output]).should_not be_nil
      (/Unexpected error occurred/ =~ result[:output]).should be_nil
      verify_task_result("rollback", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'nodeport_not_used' should fail when a node port is being used", tags: ["nodeport_not_used"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_nodeport")
      result = ShellCmd.run_testsuite("nodeport_not_used")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(NodePort is being used)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'nodeport_not_used' should pass when a node port is not being used", tags: ["nodeport_not_used"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("nodeport_not_used")
      result[:status].success?.should be_true
      (/(PASSED).*(NodePort is not used)/ =~ result[:output]).should_not be_nil
      verify_task_result("nodeport_not_used", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'hostport_not_used' should fail when a Deployment uses a host port", tags: ["hostport_not_used"] do
    begin
      # The check reads the containers of the pod template (#2687).
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-hostport-deployment")
      result = ShellCmd.run_testsuite("hostport_not_used")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(HostPort is being used)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/hostport-deployment.*\(container hostport-deployment\): using hostPort 18081 for containerPort 8080/ =~ result[:output]).should_not be_nil
      verify_task_result("hostport_not_used", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'hostport_not_used' should fail when a bare Pod uses a host port", tags: ["hostport_not_used"] do
    begin
      # A Pod has no spec.template; the check must still see its containers (#2486).
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-hostport-pod")
      result = ShellCmd.run_testsuite("hostport_not_used")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(HostPort is being used)/ =~ result[:output]).should_not be_nil
      (/impacted: Pod\/hostport-pod.*\(container hostport-pod\): using hostPort 18080 for containerPort 8080/ =~ result[:output]).should_not be_nil
      verify_task_result("hostport_not_used", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'hostport_not_used' should pass when a node port is not being used", tags: ["hostport_not_used"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("hostport_not_used")
      result[:status].success?.should be_true
      (/(PASSED).*(HostPort is not used)/ =~ result[:output]).should_not be_nil
      verify_task_result("hostport_not_used", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'hardcoded_ip_addresses_in_k8s_runtime_configuration' should fail when a hardcoded ip is found in the K8s configuration", tags: ["ip_addresses"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_coredns_hardcoded_ips")
      result = ShellCmd.run_testsuite("hardcoded_ip_addresses_in_k8s_runtime_configuration", cmd_prefix: "CNTI_TESTSUITE_LOG_LEVEL=info")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Hard-coded IP addresses found in the runtime K8s configuration)/ =~ result[:output]).should_not be_nil
      # each hit is attributed to the resource it sits in, with the address (#2490 follow-up)
      (/impacted: [A-Za-z]+\/[^ ]+ in [^ ]+: hard-coded IP \d+\.\d+\.\d+\.\d+ at line \d+:/ =~ result[:output]).should_not be_nil
      (/> remediation: .*hardcoded_ip_exceptions/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'hardcoded_ip_addresses_in_k8s_runtime_configuration' should not read CRD descriptions or non-octet numbers as addresses", tags: ["ip_addresses"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-crd-descriptions/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("hardcoded_ip_addresses_in_k8s_runtime_configuration")
      result[:status].success?.should be_true
      (/(PASSED).*(No hard-coded IP addresses found in the runtime K8s configuration)/ =~ result[:output]).should_not be_nil
      verify_task_result("hardcoded_ip_addresses_in_k8s_runtime_configuration", "passed")
    ensure
      ShellCmd.cnf_uninstall()
    end
  end

  it "'hardcoded_ip_addresses_in_k8s_runtime_configuration' should ignore addresses in comment lines of a ConfigMap's files", tags: ["ip_addresses"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-commented-ips --skip-wait-for-install")
      result = ShellCmd.run_testsuite("hardcoded_ip_addresses_in_k8s_runtime_configuration")
      result[:status].success?.should be_true
      (/(PASSED).*(No hard-coded IP addresses found in the runtime K8s configuration)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'hardcoded_ip_addresses_in_k8s_runtime_configuration' should pass when no ip addresses are found in the K8s configuration", tags: ["ip_addresses"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("hardcoded_ip_addresses_in_k8s_runtime_configuration")
      result[:status].success?.should be_true
      (/(PASSED).*(No hard-coded IP addresses found in the runtime K8s configuration)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'secrets_used' should pass when secrets are provided as volumes and used by a container", tags: ["secrets"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_secret_volume/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("secrets_used")
      result[:status].success?.should be_true
      (/(PASSED).*(Secrets defined and used)/ =~ result[:output]).should_not be_nil
      verify_task_result("secrets_used", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'secrets_used' should fail when a secret is shipped as a volume that no container mounts", tags: ["secrets"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_unmounted_secret_volume/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("secrets_used")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Secrets shipped and references do not match)/ =~ result[:output]).should_not be_nil
      (/impacted: Secret\/.* shipped by the CNF but read by none of its/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'secrets_used' should pass when secrets are provided as environment variables and used by a container", tags: ["secrets"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_secret_env/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("secrets_used")
      result[:status].success?.should be_true
      (/(PASSED).*(Secrets defined and used)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'secrets_used' should fail when a shipped secret is not referenced by any container", tags: ["secrets"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_secret_env_no_ref/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("secrets_used")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Secrets shipped and references do not match)/ =~ result[:output]).should_not be_nil
      (/impacted: Secret\/.* shipped by the CNF but read by none of its/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'secrets_used' should be skipped when no secret volumes are mounted or no container secrets are provided (secrets ignored)`", tags: ["secrets"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("secrets_used")
      result[:status].success?.should be_true
      (/(N\/A).*(Secrets not used)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'immutable_configmap' fail with some mutable configmaps in container env or volume mount", tags: ["immutable_configmap"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/ndn-mutable-configmap")
      result = ShellCmd.run_testsuite("immutable_configmap")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Found \d+ mutable configmap use\(s\))/ =~ result[:output]).should_not be_nil
      (/impacted: (Deployment|Pod)\/.* in .*: ConfigMap .* (mounted as volume .* in container .*|used in env of container .*) is mutable/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'immutable_configmap' pass with all immutable configmaps in container env or volume mounts", tags: ["immutable_configmap"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/ndn-immutable-configmap")
      result = ShellCmd.run_testsuite("immutable_configmap")
      result[:status].success?.should be_true
      (/(PASSED).*(All volume or container mounted configmaps immutable)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'require_labels' should fail if a cnf does not have the app.kubernetes.io/name label", tags: ["require_labels"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_nonroot/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("require_labels")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Pods should have the app.kubernetes.io\/name label)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'require_labels' should pass if a cnf has the app.kubernetes.io/name label", tags: ["require_labels"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("require_labels")
      result[:status].success?.should be_true
      (/(PASSED).*(Pods have the app.kubernetes.io\/name label)/ =~ result[:output]).should_not be_nil
      verify_task_result("require_labels", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'default_namespace' should fail if a cnf creates resources in the default namespace", tags: ["default_namespace"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns_default_namespace")
      result = ShellCmd.run_testsuite("default_namespace")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Resources are created in the default namespace)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      KubectlClient::Wait.wait_for_terminations()
    end
  end

  it "'default_namespace' should pass if a cnf does not create resources in the default namespace", tags: ["default_namespace"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_latest_tag")
      result = ShellCmd.run_testsuite("default_namespace")
      result[:status].success?.should be_true
      (/(PASSED).*(default namespace is not being used)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      KubectlClient::Wait.wait_for_terminations()
    end
  end

  it "'latest_tag' should fail if a cnf has containers that use images with the latest tag", tags: ["latest_tag"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_latest_tag")
      result = ShellCmd.run_testsuite("latest_tag")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Container images are using the latest tag)/ =~ result[:output]).should_not be_nil
      (/impacted: Pod\/nginx in .* \(container nginx\): image nginxinc\/nginx-unprivileged:latest uses the latest tag/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'latest_tag' should pass if a cnf does not have containers that use images with the latest tag", tags: ["latest_tag"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_nonroot")
      result = ShellCmd.run_testsuite("latest_tag")
      result[:status].success?.should be_true
      (/(PASSED).*(Container images are not using the latest tag)/ =~ result[:output]).should_not be_nil
      verify_task_result("latest_tag", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'versioned_tag' should pass when every image is pinned to a version", tags: ["versioned_tag"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_coredns")
      result = ShellCmd.run_testsuite("versioned_tag")
      result[:status].success?.should be_true
      (/(PASSED).*(Container images use versioned tags)/ =~ result[:output]).should_not be_nil
      (/> Deployment\/coredns-coredns in .* container coredns: .*coredns:[\d.]+ is versioned/ =~ result[:output]).should_not be_nil
      verify_task_result("versioned_tag", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'versioned_tag' should fail on a latest tag and name the container", tags: ["versioned_tag"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_latest_tag")
      result = ShellCmd.run_testsuite("versioned_tag")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(1 container image\(s\) do not use versioned tags)/ =~ result[:output]).should_not be_nil
      (/impacted: Pod\/nginx in nginx-stuff \(container nginx\): image nginxinc\/nginx-unprivileged:latest uses the latest tag/ =~ result[:output]).should_not be_nil
      verify_task_result("versioned_tag", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'versioned_tag' should fail on an untagged image and pass the versioned container beside it", tags: ["versioned_tag"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-unversioned-tags")
      result = ShellCmd.run_testsuite("versioned_tag")
      result[:status].exit_code.should eq(1)
      (/impacted: Deployment\/unversioned in unversioned \(container untagged\): image nginxinc\/nginx-unprivileged has no tag \(implicitly latest\)/ =~ result[:output]).should_not be_nil
      (/> Deployment\/unversioned in unversioned container versioned: nginxinc\/nginx-unprivileged:1.29 is versioned/ =~ result[:output]).should_not be_nil
      verify_task_result("versioned_tag", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'latest_tag' should require a cnf be installed to run", tags: ["latest_tag"] do
    # NOTE: Purposefully not installing a CNF to test
    result = ShellCmd.run_testsuite("latest_tag")
    result[:status].success?.should be_false
    (/You must install a CNF first./ =~ result[:output]).should_not be_nil
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
  it "'alpha_k8s_apis' should fail when a manifest declares or bundles an alpha Kubernetes API", tags: ["alpha_k8s_apis"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-k8s-alpha-apis/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("alpha_k8s_apis")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(CNF uses Kubernetes alpha APIs)/ =~ result[:output]).should_not be_nil
      (/impacted: TCPRoute\/k8s-alpha-apis in k8s-alpha-apis: declared with the alpha API gateway.networking.k8s.io\/v1alpha2/ =~ result[:output]).should_not be_nil
      (/impacted: CustomResourceDefinition\/tcproutes.gateway.networking.k8s.io: serves only alpha version\(s\) of the Kubernetes API gateway.networking.k8s.io: v1alpha2/ =~ result[:output]).should_not be_nil
      verify_task_result("alpha_k8s_apis", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'alpha_k8s_apis' should pass a CNF whose own CRD and resources are at v1alpha1", tags: ["alpha_k8s_apis"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-alpha-apis/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("alpha_k8s_apis")
      result[:status].success?.should be_true
      (/(PASSED).*(CNF does not use Kubernetes alpha APIs)/ =~ result[:output]).should_not be_nil
      (/impacted: CustomResourceDefinition\/widgets.example.com/ =~ result[:output]).should be_nil
      verify_task_result("alpha_k8s_apis", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'alpha_k8s_apis' should pass when no alpha APIs are used", tags: ["alpha_k8s_apis"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("alpha_k8s_apis")
      result[:status].success?.should be_true
      (/(PASSED).*(CNF does not use Kubernetes alpha APIs)/ =~ result[:output]).should_not be_nil
      verify_task_result("alpha_k8s_apis", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'hugepages_volumes' should be N/A on a cnf with no hugepages volume", tags: ["hugepages_volumes"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("hugepages_volumes")
      result[:status].success?.should be_true
      (/(N\/A).*(No pod declares a hugepages emptyDir volume)/ =~ result[:output]).should_not be_nil
      verify_task_result("hugepages_volumes", "na")
    ensure
      result = ShellCmd.cnf_uninstall
    end
  end

  it "'hugepages_volumes' should pass when the volume is backed by a matching request", tags: ["hugepages_volumes"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_hugepages --skip-wait-for-install")
      result = ShellCmd.run_testsuite("hugepages_volumes")
      result[:status].success?.should be_true
      (/(PASSED).*(Every hugepages volume is backed by a matching hugepages request)/ =~ result[:output]).should_not be_nil
      verify_task_result("hugepages_volumes", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
    end
  end

  it "'hugepages_volumes' should fail when a hugepages volume has no backing request", tags: ["hugepages_volumes"] do
    begin
      # The manifest is accepted by the API server (the pod fails only on the
      # node), so it installs with --skip-wait-for-install and the test runs.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_hugepages_unbacked --skip-wait-for-install")
      result = ShellCmd.run_testsuite("hugepages_volumes")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(hugepages volume\(s\) without a matching request)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/hugepages-unbacked.*is not backed by/ =~ result[:output]).should_not be_nil
      verify_task_result("hugepages_volumes", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
    end
  end

  it "'exclusive_cpus' should be N/A on a cnf that declares no latency-sensitive workload", tags: ["exclusive_cpus"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("exclusive_cpus")
      result[:status].success?.should be_true
      (/(N\/A).*(No workloads declared latency_sensitive)/ =~ result[:output]).should_not be_nil
      verify_task_result("exclusive_cpus", "na")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'exclusive_cpus' should pass when the named container is whole-CPU in a Guaranteed pod (fractional sidecar allowed)", tags: ["exclusive_cpus"] do
    begin
      # The test reads the live pods' QoS class and defaulted requests, so the
      # pods must exist — do not skip waiting for install.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_exclusive_cpus")
      result = ShellCmd.run_testsuite("exclusive_cpus")
      result[:status].success?.should be_true
      (/(PASSED).*(Latency-sensitive workloads are eligible for exclusive CPUs)/ =~ result[:output]).should_not be_nil
      verify_task_result("exclusive_cpus", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'exclusive_cpus' should pass a multi-workload cnf, judging only the named workload", tags: ["exclusive_cpus"] do
    begin
      # Only flagged-upf is latency_sensitive; unflagged-web sets no resources and
      # must be ignored, so the CNF passes.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_exclusive_cpus_multi")
      result = ShellCmd.run_testsuite("exclusive_cpus")
      result[:status].success?.should be_true
      (/(PASSED).*(Latency-sensitive workloads are eligible for exclusive CPUs)/ =~ result[:output]).should_not be_nil
      verify_task_result("exclusive_cpus", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'exclusive_cpus' should fail when the named container requests a fractional cpu", tags: ["exclusive_cpus"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_exclusive_cpus_fail")
      result = ShellCmd.run_testsuite("exclusive_cpus")
      result[:status].exit_code.should eq(1)
      expected = /impacted: Deployment\/exclusive-cpus-app-fail.*\(container app\):.*whole number of CPUs/
      unless expected =~ result[:output]
        fail "no per-container whole-CPU finding; impacted lines were:\n#{result[:output].lines.select(&.includes?("impacted:")).join}"
      end
      (/remediation: For each latency-sensitive workload make its pods Guaranteed/ =~ result[:output]).should_not be_nil
      verify_task_result("exclusive_cpus", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'exclusive_cpus' includes init containers in the pod QoS check and blames the init container", tags: ["exclusive_cpus"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_exclusive_cpus_bad_init")
      result = ShellCmd.run_testsuite("exclusive_cpus")
      result[:status].exit_code.should eq(1)
      # The init container makes the pod Burstable; the finding is attributed to
      # it, not to the whole-CPU "1000m" main container.
      (/impacted: Deployment\/exclusive-cpus-bad-init.*\(container setup\):/ =~ result[:output]).should_not be_nil
      impacted = result[:output].lines.select(&.includes?("impacted:")).join
      impacted.should_not contain("container app")
      verify_task_result("exclusive_cpus", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'exclusive_cpus' should skip when a named latency-sensitive workload is absent", tags: ["exclusive_cpus"] do
    begin
      # The config names a workload the CNF does not deploy: nothing to measure.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_exclusive_cpus_missing --skip-wait-for-install")
      result = ShellCmd.run_testsuite("exclusive_cpus")
      (/(SKIPPED).*(Could not measure the latency-sensitive workload)/ =~ result[:output]).should_not be_nil
      (/matches no workload of the CNF/ =~ result[:output]).should_not be_nil
      verify_task_result("exclusive_cpus", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end
end
