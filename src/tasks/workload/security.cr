# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "CNF containers should be isolated from one another and the host.  The CNF Test suite uses tools like Sysdig Inspect and gVisor"
category_task "security", [
    "symlink_file_system",
    "seccomp_profile",
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

# The sysctls Pod Security Standards call safe; anything else set on a pod is
# what the kyverno policy flags.
SAFE_SYSCTLS = ["kernel.shm_rmid_forced", "net.ipv4.ip_local_port_range", "net.ipv4.ip_unprivileged_port_start",
                "net.ipv4.tcp_syncookies", "net.ipv4.ping_group_range", "net.ipv4.ip_local_reserved_ports"]

# The sysctl names a workload sets outside the safe set, read from its live spec.
def unsafe_sysctls_of(kind : String, name : String, namespace : String?) : Array(String)
  live = KubectlClient::Get.resource(kind, name, namespace)
  pod_spec = live.dig?("spec", "template", "spec") || live.dig?("spec")
  sysctls = pod_spec.try(&.dig?("securityContext", "sysctls")).try(&.as_a?) || [] of JSON::Any
  sysctls.compact_map { |s| s.dig?("name").try(&.as_s?) }.reject { |n| SAFE_SYSCTLS.includes?(n) }
rescue
  [] of String
end

desc "Check if pods in the CNF use sysctls with restricted values"
scored_task "sysctls",
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install
    policy_path = Kyverno.policy_path("pod-security/baseline/restrict-sysctls/restrict-sysctls.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)

    # Each unsafe sysctl is a finding of its own, so a documented exception
    # (common.exceptions) can cover exactly the sysctls a workload needs.
    failed = false
    failures.each do |failure|
      failure.resources.each do |resource|
        unsafe = unsafe_sysctls_of(resource.kind, resource.name, resource.namespace)
        if unsafe.empty?
          failed = true unless Exceptions.judge(result, config, t.name, resource.kind, resource.name, resource.namespace, nil, nil, failure.message)
          next
        end
        unsafe.each do |sysctl|
          failed = true unless Exceptions.judge(result, config, t.name, resource.kind, resource.name, resource.namespace, nil, sysctl, "sysctl #{sysctl} is outside the safe set")
        end
      end
    end

    if failed
      result.failed("Restricted values for are being used for sysctls")
    elsif result.result_excepted.empty?
      result.passed("No restricted values found for sysctls")
    else
      result.passed("No restricted values found for sysctls beyond the documented exceptions")
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
            options = Kyverno::Findings.selinux_options(resource.kind, resource.name, resource.namespace)
            if options.empty?
              result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: failure.message)
            else
              options.each do |o|
                reason = "seLinuxOptions #{o[:options]}"
                container = o[:scope] == "pod" ? nil : o[:scope]
                result.add_impacted_resource(resource.kind, resource.name, resource.namespace, container: container, reason: reason)
              end
            end
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
          mounts = Kyverno::Findings.socket_mounts(resource.kind, resource.name, resource.namespace)
          if mounts.empty?
            result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: failure.message)
          else
            mounts.each do |m|
              reason = "volume #{m[:volume]} mounts host path #{m[:path]}"
              if m[:containers].empty?
                result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: reason)
              else
                m[:containers].each { |c| result.add_impacted_resource(resource.kind, resource.name, resource.namespace, container: c, reason: reason) }
              end
            end
          end
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
    violations = 0
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      # The resource's own containers - init and ephemeral ones included - judged
      # by their own securityContext, never by a name shared with some privileged
      # container elsewhere in the cluster.
      resource_passed = true
      live = KubectlClient::Get.resource(resource["kind"], resource["name"], resource["namespace"])
      pod_spec = live.dig?("spec", "template", "spec") || live.dig?("spec")
      init_names = (pod_spec.try(&.dig?("initContainers")).try(&.as_a?) || [] of JSON::Any).compact_map { |c| c.dig?("name").try(&.as_s?) }
      KubectlClient::Get.resource_all_containers(resource["kind"], resource["name"], resource["namespace"]).each do |container|
        container_name = container.dig?("name").try(&.as_s) || ""
        next unless container.dig?("securityContext", "privileged") == true
        finding = init_names.includes?(container_name) ? "privileged init container" : "privileged container"
        # white_list_container_names is the older, reason-less form of an
        # exception; common.exceptions carries the reason.
        if white_list_container_names.includes?(container_name)
          result.add_excepted(resource["kind"], resource["name"], resource["namespace"], container: container_name,
            finding: finding, reason: "listed in white_list_container_names")
          next
        end
        next if Exceptions.judge(result, config, t.name, resource["kind"], resource["name"], resource["namespace"], container_name, nil, finding)
        violations += 1
        resource_passed = false
      end
      resource_passed
    end
    if task_response && result.result_excepted.empty?
      result.passed("No privileged containers")
    elsif task_response
      result.passed("No privileged containers beyond the documented exceptions")
    else
      result.failed("Found #{violations} privileged containers")
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

    # The host network is a pod-level setting: a documented exception
    # (common.exceptions) names the workload resource.
    failed = false
    test_report.failed_resources.each do |r|
      findings = r.paths.empty? ? [r.alert_message.to_s] : r.paths.map { |path| r.reason_for(path) }
      findings.each do |finding|
        failed = true unless Exceptions.judge(result, config, t.name, r.kind, r.name, r.namespace, nil, nil, finding)
      end
    end

    if failed
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found host network attached to pod")
    elsif result.result_excepted.empty?
      result.passed("No host network attached to pod")
    else
      result.passed("No host network attached to pod beyond the documented exceptions")
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

# The seccomp profile types Pod Security Standards (restricted) accept.
SECCOMP_PROFILES = ["RuntimeDefault", "Localhost"]

desc "Check if every container runs under a seccomp profile"
scored_task "seccomp_profile",
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # A container's profile is its own securityContext.seccompProfile, else the
    # pod's; unset means Unconfined on every runtime. Judged per container, so
    # the finding names what to fix (#2582).
    violations = 0
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      live = KubectlClient::Get.resource(resource["kind"], resource["name"], resource["namespace"])
      pod_spec = live.dig?("spec", "template", "spec") || live.dig?("spec")
      pod_profile = pod_spec.try(&.dig?("securityContext", "seccompProfile", "type")).try(&.as_s?)
      resource_passed = true
      KubectlClient::Get.resource_all_containers(resource["kind"], resource["name"], resource["namespace"]).each do |container|
        container_name = container.dig?("name").try(&.as_s) || ""
        profile = container.dig?("securityContext", "seccompProfile", "type").try(&.as_s?) || pod_profile
        next if SECCOMP_PROFILES.includes?(profile)
        reason = profile ? "seccompProfile.type is #{profile}" : "no seccompProfile on the container or its pod"
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], container: container_name, reason: reason)
        violations += 1
        resource_passed = false
      end
      resource_passed
    end
    if task_response
      result.passed("Every container runs under a seccomp profile")
    else
      result.append_remediation("Set securityContext.seccompProfile.type: RuntimeDefault on the pod, or per container, or a Localhost profile of your own.")
      result.failed("Found #{violations} container(s) without a seccomp profile")
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

    # Each added capability is a finding of its own, so a documented exception
    # (common.exceptions) can cover exactly the capability a container needs.
    failed = false
    test_report.failed_resources.each do |r|
      if r.paths.empty?
        failed = true unless Exceptions.judge(result, config, t.name, r.kind, r.name, r.namespace, nil, nil, r.alert_message.to_s)
        next
      end
      r.paths.each do |path|
        capability = r.value_for(path)
        finding = capability ? "capability #{capability} added (#{path})" : r.reason_for(path)
        failed = true unless Exceptions.judge(result, config, t.name, r.kind, r.name, r.namespace, r.container_for(path), capability, finding)
      end
    end

    if failed
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers with insecure capabilities")
    elsif result.result_excepted.empty?
      result.passed("Containers with insecure capabilities were not found")
    else
      result.passed("Containers with insecure capabilities were not found beyond the documented exceptions")
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

# CNIs that enforce NetworkPolicy, by the name of the agent they run on every
# node. flannel implements none: a policy that cannot take effect is not the
# CNF's doing, so ingress_egress_blocked is not applicable there. kindnet
# counts: kind ships kube-network-policies inside kindnetd since v0.23.
NETWORK_POLICY_CNI_AGENTS = /calico|cilium|antrea|weave|kube-router|ovn|canal|kindnet/i

def network_policy_enforced? : Bool
  daemonsets = KubectlClient::Get.resource("daemonsets", all_namespaces: true)
  items = daemonsets["items"]?.try(&.as_a?) || [] of JSON::Any
  items.any? { |ds| ds.dig?("metadata", "name").to_s =~ NETWORK_POLICY_CNI_AGENTS }
end

desc "Check Ingress and Egress traffic policy"
scored_task "ingress_egress_blocked",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:kubescape_scan"],
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    unless network_policy_enforced?
      result.na("No CNI that enforces NetworkPolicy in this cluster: an ingress/egress policy could not take effect")
      next
    end

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
