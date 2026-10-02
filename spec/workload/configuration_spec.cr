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
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'rolling_update' should skip with remediation when no test tag is configured", tags: ["rolling_update"] do
    begin
      # sample-coredns-cnf declares no container_names at all.
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_update")
      (/(SKIPPED).*(No rolling_update_test_tag configured for any container)/ =~ result[:output]).should_not be_nil
      (/remediation: Please add the container name coredns and a corresponding rolling_update_test_tag/ =~ result[:output]).should_not be_nil
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

  it "'rollback' should skip with remediation when no rollback_from_tag is configured", tags: ["rollback"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rollback")
      (/(SKIPPED).*(No usable rollback_from_tag configured for any container)/ =~ result[:output]).should_not be_nil
      (/remediation: Please add the container name coredns and a corresponding rollback_from_tag/ =~ result[:output]).should_not be_nil
      verify_task_result("rollback", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  # TODO: figure out failing test for rollback

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

  it "'hostport_not_used' should fail when a host port is being used", tags: ["hostport_not_used"] do
    begin
      # The test reads the ports of the Deployment, which exists as soon as it
      # is applied: no need to wait for the application, which takes over a
      # minute to start and once did not start at all (#2669).
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_hostport --skip-wait-for-install")
      result = ShellCmd.run_testsuite("hostport_not_used")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(HostPort is being used)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
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

  it "'secrets_used' should be skipped when secrets are provided as volumes and not mounted by a container", tags: ["secrets"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_unmounted_secret_volume/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("secrets_used")
      result[:status].success?.should be_true
      (/(N\/A).*(Secrets not used)/ =~ result[:output]).should_not be_nil
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

  it "'secrets_used' should skip when secrets are not referenced as environment variables by a container", tags: ["secrets"] do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_secret_env_no_ref/cnti-testsuite.yaml --skip-wait-for-install")
      result = ShellCmd.run_testsuite("secrets_used")
      result[:status].success?.should be_true
      (/(N\/A).*(Secrets not used)/ =~ result[:output]).should_not be_nil
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
  it "'alpha_k8s_apis' should fail when a manifest declares or serves only alpha APIs", tags: ["alpha_k8s_apis"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-alpha-apis/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("alpha_k8s_apis")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(CNF uses Kubernetes alpha APIs)/ =~ result[:output]).should_not be_nil
      (/impacted: CustomResourceDefinition\/widgets.example.com: serves only alpha version\(s\): v1alpha1/ =~ result[:output]).should_not be_nil
      verify_task_result("alpha_k8s_apis", "failed")
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
