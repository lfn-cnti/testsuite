# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "CNF containers should be isolated from one another and the host.  The CNF Test suite uses tools like Sysdig Inspect and gVisor"
category_task "security", [
    "symlink_file_system",
    "privilege_escalation",
    "insecure_capabilities",
    "memory_limits",
    "cpu_limits",
    "linux_hardening",
    "ingress_egress_blocked",
    "host_pid_ipc_privileges",
    "non_root_containers",
    "privileged_containers",
    "immutable_file_systems",
    "hostpath_mounts",
    "container_sock_mounts",
    "external_ips",
    "selinux_options",
    "sysctls",
    "host_network",
    "service_account_mapping",
    "application_credentials"
  ]

desc "Check if pods in the CNF use sysctls with restricted values"
scored_task "sysctls",
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install
    policy_path = Kyverno.policy_path("pod-security/baseline/restrict-sysctls/restrict-sysctls.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)

    if failures.size == 0
      result.passed("No restricted values found for sysctls")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: failure.message)
        end
      end
      result.failed("Restricted values for are being used for sysctls")
    end
  end
end

desc "Check if the CNF has services with external IPs configured"
scored_task "external_ips",
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install
    policy_path = Kyverno.best_practice_policy("restrict-service-external-ips/restrict-service-external-ips.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

    resource_keys = CNFManager.resource_refs(args, config, ["service"]) do |service|
      "#{service[:namespace]},#{service[:kind]}/#{service[:name]}".downcase
    end    

    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)
    
    if failures.size == 0
      result.passed("Services are not using external IPs")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: failure.message)
        end
      end
      result.failed("Services are using external IPs")
    end
  end
end

desc "Check if the CNF or the cluster resources have custom SELinux options"
scored_task "selinux_options",
  type: CNFManager::TestType::Essential,
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install
    check_policy_path = Kyverno::CustomPolicies::SELinuxEnabled.new.policy_path
    check_failures = Kyverno::PolicyAudit.run(check_policy_path, EXCLUDE_NAMESPACES)

    disallow_policy_path = Kyverno.policy_path("pod-security/baseline/disallow-selinux/disallow-selinux.yaml")
    disallow_failures = Kyverno::PolicyAudit.run(disallow_policy_path, EXCLUDE_NAMESPACES)

    #TODO check for AppArmor as well, and the cnf should have either selinux or apparmor
    # IF SELinux is not enabled, skip this test
    # Else check for SELinux options

    resource_keys = CNFManager.workload_resource_keys(args, config)
    check_failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, check_failures)

    if check_failures.size == 0
      # No seLinuxOptions at all: nothing escalatory is configured, which is
      # exactly what certification asks for.
      result.passed("Pods do not set seLinuxOptions")
    else
      failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, disallow_failures)

      if failures.size == 0
        result.passed("Pods are not using custom SELinux options that can be used for privilege escalations")
      else
        failures.each do |failure|
          failure.resources.each do |resource|
            result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: failure.message)
          end
        end
        result.failed("Pods are using custom SELinux options that can be used for privilege escalations")
      end
    end
  end
end

desc "Check if the CNF is running containers with container sock mounts"
scored_task "container_sock_mounts",
  type: CNFManager::TestType::Essential,
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install
    policy_path = Kyverno.best_practice_policy("disallow-cri-sock-mount/disallow-cri-sock-mount.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

    # The audit covers the cluster; only the CNF's own resources are judged.
    resource_keys = CNFManager.workload_resource_keys(args, config)
    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)

    if failures.size == 0
      result.passed("Container engine daemon sockets are not mounted as volumes")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: failure.message)
        end
      end
      result.failed("Container engine daemon sockets are mounted as volumes")
    end
  end
end

desc "Check if any containers are running in privileged mode"
scored_task "privileged_containers",
  type: CNFManager::TestType::Essential,
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    white_list_container_names = config.common.white_list_container_names
    Log.debug { "white_list_container_names #{white_list_container_names.inspect}" }
    violation_list = [] of NamedTuple(kind: String, name: String, container: String, namespace: String)
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      # The resource's own containers - init and ephemeral ones included - judged
      # by their own securityContext, never by a name shared with some privileged
      # container elsewhere in the cluster.
      resource_passed = true
      KubectlClient::Get.resource_all_containers(resource["kind"], resource["name"], resource["namespace"]).each do |container|
        container_name = container.dig?("name").try(&.as_s) || ""
        next if white_list_container_names.includes?(container_name)
        next unless container.dig?("securityContext", "privileged") == true
        violation_list << {kind: resource["kind"], name: resource["name"], container: container_name, namespace: resource["namespace"]}
        resource_passed = false
      end
      resource_passed
    end
    Log.debug { "violator list: #{violation_list.flatten}" }
    if task_response
      result.passed("No privileged containers")
    else
      violation_list.each do |violation|
        result.add_impacted_resource(violation[:kind], violation[:name], violation[:namespace],
          container: violation[:container], reason: "privileged container")
      end
      result.failed("Found #{violation_list.size} privileged containers")
    end
  end
end

desc "Check if any containers are running in privileged mode"
scored_task "privilege_escalation",
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Allow privilege escalation")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("No containers that allow privilege escalation were found")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers that allow privilege escalation")
    end
  end
end

desc "Check if an attacker can use symlink for arbitrary host file system access."
scored_task "symlink_file_system",
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "CVE-2021-25741 - Using symlink for arbitrary host file system access.")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("No containers allow a symlink attack")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers that allow a symlink attack")
    end
  end
end

desc "Check if applications credentials are in configuration files."
scored_task "application_credentials",
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Applications credentials in configuration files")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("No applications credentials in configuration files")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found applications credentials in configuration files")
    end
  end
end

desc "Check if potential attackers may gain access to a POD and inherit access to the entire host network. For example, in AWS case, they will have access to the entire VPC."
scored_task "host_network",
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "HostNetwork access")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("No host network attached to pod")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found host network attached to pod")
    end
  end
end

desc "Potential attacker may gain access to a POD and steal its service account token. Therefore, it is recommended to disable automatic mapping of the service account tokens in service account configuration and enable it only for PODs that need to use them."
scored_task "service_account_mapping",
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Automatic mapping of service account")
    test_report = Kubescape.parse_test_report(test_json)
    # Kubescape reports the workloads that will actually mount a token (a
    # pod-level automountServiceAccountToken overrides the service account's),
    # so match on the CNF's workloads, not its ServiceAccount objects.
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("No service accounts automatically mapped")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Service accounts automatically mapped")
    end
  end
end

desc "Check if security services are being used to harden the application"
scored_task "linux_hardening",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Linux hardening")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Security services are being used to harden applications")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found resources that do not use security services")
    end
  end
end

desc "Check if the containers have insecure capabilities."
scored_task "insecure_capabilities",
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Insecure capabilities")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Containers with insecure capabilities were not found")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers with insecure capabilities")
    end
  end
end

desc "Check if the containers have CPU limits set"
scored_task "cpu_limits",
  type: CNFManager::TestType::Essential,
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Ensure CPU limits are set")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Containers have CPU limits set")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers without CPU limits set")
    end
  end
end

desc "Check if the containers have memory limits set"
scored_task "memory_limits",
  type: CNFManager::TestType::Essential,
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Ensure memory limits are set")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Containers have memory limits set")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers without memory limits set")
    end
  end
end

desc "Check Ingress and Egress traffic policy"
scored_task "ingress_egress_blocked",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Ingress and Egress blocked")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Ingress and Egress traffic blocked on pods")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Ingress and Egress traffic not blocked on pods")
    end
  end
end

desc "Check the Host PID/IPC privileges of the containers"
scored_task "host_pid_ipc_privileges",
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Host PID/IPC privileges")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("No containers with hostPID and hostIPC privileges")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers with hostPID and hostIPC privileges")
    end
  end
end

desc "Check if the containers are running with non-root user with non-root group membership"
scored_task "non_root_containers",
  type: CNFManager::TestType::Essential,
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Non-root containers")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Containers are running with non-root user with non-root group membership")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers running with root user or user with root group membership")
    end
  end
end

desc "Check if containers have immutable file systems"
scored_task "immutable_file_systems",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Immutable container filesystem")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Containers have immutable file systems")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers with mutable file systems")
    end
  end
end

desc "Check if containers have hostPath mounts"
scored_task "hostpath_mounts",
  type: CNFManager::TestType::Essential,
  deps: ["setup:install_kubescape"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    kubescape_control_id = "C-0048"
    Kubescape.scan(control_id: kubescape_control_id)
    results_file = Kubescape.control_results_file(kubescape_control_id)
    results_json = Kubescape.parse(results_file)
    test_json = Kubescape.test_by_test_name(results_json, "HostPath mount")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      result.passed("Containers do not have hostPath mounts")
    else
      Kubescape.report_failed_resources(test_report, result)
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers with hostPath mounts")
    end
  end
end
