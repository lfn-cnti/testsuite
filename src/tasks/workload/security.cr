# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../utils/sbom_detection.cr"
require "../utils/pod_security.cr"

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
    "dedicated_service_account",
    "application_credentials",
    "sbom_available",
    "pod_security_baseline"
  ]

# Names of the sysctls a resource sets in its pod security context; empty
# when it sets none or cannot be read.
def pod_sysctl_names(kind : String, name : String, namespace : String?) : Array(String)
  resource = KubectlClient::Get.resource(kind, name, namespace)
  pod_spec = resource.dig?("spec", "template", "spec") || resource.dig?("spec")
  sysctls = pod_spec.try(&.dig?("securityContext", "sysctls")).try(&.as_a?) || [] of JSON::Any
  sysctls.compact_map(&.dig?("name").try(&.as_s?))
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

    if failures.size == 0
      result.passed("No restricted values found for sysctls")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          names = pod_sysctl_names(resource.kind, resource.name, resource.namespace)
          reason = names.empty? ? failure.message : "sets sysctls #{names.join(", ")}. #{failure.message}"
          result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: reason)
        end
      end
      result.failed("Found resources that set sysctls outside the safe set")
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
    violation_list = [] of NamedTuple(kind: String, name: String, container: String, namespace: String, init: Bool)
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
        next if white_list_container_names.includes?(container_name)
        next unless container.dig?("securityContext", "privileged") == true
        violation_list << {kind: resource["kind"], name: resource["name"], container: container_name, namespace: resource["namespace"], init: init_names.includes?(container_name)}
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
          container: violation[:container], reason: violation[:init] ? "privileged init container" : "privileged container")
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
      Kubescape.report_failed_resources(test_report, result, finding: "securityContext.allowPrivilegeEscalation is not set to false")
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

    # The scanner matches variables by name; what it names is resolved in
    # the object, so the details say which variable is meant and a plain
    # switch such as ALLOW_EMPTY_PASSWORD=yes is not taken for a credential.
    found = 0
    test_report.failed_resources.each do |r|
      if r.paths.empty?
        found += 1
        result.add_impacted_resource(r.kind, r.name, r.namespace, reason: r.alert_message)
        next
      end
      object = begin
        KubectlClient::Get.resource(r.kind, r.name, r.namespace)
      rescue
        nil
      end
      credentials = Kubescape.credential_findings(object, r.paths)
      credentials[:switches].each do |switch|
        result.append_description("#{r.kind}/#{r.name} in #{r.namespace}: #{switch} is an on/off switch, not a stored credential")
      end
      credentials[:findings].each do |finding|
        found += 1
        result.add_impacted_resource(r.kind, r.name, r.namespace, container: finding[:container], reason: finding[:reason])
      end
    end

    if found == 0
      result.passed("No applications credentials in configuration files")
    else
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
      Kubescape.report_failed_resources(test_report, result, finding: "none of AppArmor, seccomp, SELinux or Linux capabilities is defined")
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

# The effective uid and gid of each running container's first process, by
# container name, read from /proc on the node through cluster-tools. A
# container that is not running is absent.
def observed_container_owners(kind : String, name : String, namespace : String?) : Hash(String, NamedTuple(uid: Int64, gid: Int64))
  owners = {} of String => NamedTuple(uid: Int64, gid: Int64)
  return owners unless namespace
  resource = {kind: kind, name: name, namespace: namespace}
  begin
    ClusterTools.all_containers_by_resource?(resource, namespace, include_proctree: false) do |_, pid, node, _, container_status, _|
      container = container_status["name"].as_s
      status = ClusterTools.exec_by_node("cat /proc/#{pid}/status", node)
      next unless status[:status].success?
      fields = KernelIntrospection.parse_status(status[:output])
      next unless fields
      # Uid/Gid lines: real, effective, saved, filesystem.
      uid = fields["Uid"]?.try(&.split[1]?).try(&.to_i64?)
      gid = fields["Gid"]?.try(&.split[1]?).try(&.to_i64?)
      next unless uid && gid
      Log.for("observed_container_owners").info { "#{kind} #{name} container #{container} runs as uid #{uid} gid #{gid}" }
      owners[container] = {uid: uid, gid: gid}
    end
  rescue ex
    Log.for("observed_container_owners").warn { "Could not read the process owners of #{kind} #{name}: #{ex.message}" }
  end
  owners
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

    # Kubescape reads the manifest: a container that declares no user "may run
    # as root". Only the running process shows whether it does, so every
    # flagged container is checked on its node before it counts as a failure.
    root_found = false
    undeclared = [] of String
    test_report.failed_resources.each do |r|
      owners = observed_container_owners(r.kind, r.name, r.namespace)
      paths_by_container = r.paths.group_by { |path| r.container_for(path) }
      paths_by_container.each do |container, paths|
        owner = container ? owners[container]? : nil
        if owner && owner[:uid] != 0 && owner[:gid] != 0
          undeclared << "#{r.kind} #{r.name} container #{container} runs as uid #{owner[:uid]} gid #{owner[:gid]} but the manifest does not say so: #{paths.map { |path| r.reason_for(path) }.join(", ")}"
          next
        end
        root_found = true
        paths.each do |path|
          reason = owner ? "runs as uid #{owner[:uid]} gid #{owner[:gid]}; #{r.reason_for(path)}" : r.reason_for(path)
          result.add_impacted_resource(r.kind, r.name, r.namespace, container: container, reason: reason)
        end
      end
      if r.paths.empty?
        root_found = true
        result.add_impacted_resource(r.kind, r.name, r.namespace, reason: r.alert_message)
      end
    end

    unless undeclared.empty?
      result.append_description("Observed as non-root but not declared:\n#{undeclared.join("\n")}")
      result.append_remediation("Declare it: set runAsNonRoot: true and runAsGroup under the securityContext, so the kubelet refuses the container if a later image runs as root.")
    end
    if root_found
      result.append_remediation(test_report.remediation.to_s) if test_report.remediation
      result.failed("Found containers running as root user or with root group membership")
    else
      result.passed("Containers run as non-root user and group")
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

# Decides whether an SBOM is discoverable for a container image using skopeo in
# the cluster-tools pod. Returns {found: true, source: "..."} when an SBOM is
# found, {found: false} when the image is inspectable but has no SBOM, and
# {found: nil, reason: "..."} when the image itself could not be inspected
# (network/auth) so the caller can distinguish the three outcomes.
def sbom_available_for_image?(image : String) : NamedTuple(found: Bool?, source: String?, reason: String?)
  raw = ClusterTools.exec("skopeo inspect --raw docker://#{sbom_fetch_ref(image)}")
  unless raw[:status].success?
    return {found: nil, source: nil, reason: "image could not be inspected (#{raw[:error].to_s.lines.first?.to_s.strip})"}
  end

  begin
    parsed = JSON.parse(raw[:output])
  rescue
    return {found: nil, source: nil, reason: "image manifest could not be parsed"}
  end

  # 1. BuildKit / OCI attestation manifest: open each attestation manifest and
  #    require a layer whose in-toto.io/predicate-type is SPDX or CycloneDX.
  #    A provenance-only attestation (no SBOM predicate) does not count.
  sbom_attestation_digests(parsed).each do |att_digest|
    att_raw = ClusterTools.exec("skopeo inspect --raw docker://#{sbom_digest_ref(image, att_digest)}")
    next unless att_raw[:status].success?
    begin
      predicate = sbom_predicate_in_manifest(JSON.parse(att_raw[:output]), BUILDKIT_PREDICATE_ANNOTATION)
    rescue JSON::ParseException
      next
    end
    return {found: true, source: "attestation manifest (#{predicate})", reason: nil} if predicate
  end

  # 2. cosign attestation tag (.att): cosign attest --type spdxjson stores under
  #    <repo>:sha256-<hex>.att with a predicateType annotation per layer. This is
  #    the recommended path in cosign 2 (cosign attach sbom / .sbom is deprecated).
  digest = sbom_image_repo_and_digest(image)[:digest]
  if digest.nil?
    inspected = ClusterTools.exec("skopeo inspect docker://#{image} --format \"{{.Digest}}\"")
    digest = inspected[:output].strip if inspected[:status].success?
  end

  if digest && !digest.empty?
    att = ClusterTools.exec("skopeo inspect --raw docker://#{sbom_cosign_tag(image, digest, "att")}")
    if att[:status].success?
      begin
        predicate = sbom_predicate_in_manifest(JSON.parse(att[:output]), COSIGN_PREDICATE_ANNOTATION)
        return {found: true, source: "cosign attestation .att (#{predicate})", reason: nil} if predicate
      rescue JSON::ParseException
        # not parseable; fall through
      end
    end

    # 3. Fallback: deprecated cosign attach sbom / .sbom tag.
    sbom = ClusterTools.exec("skopeo inspect --raw docker://#{sbom_cosign_tag(image, digest, "sbom")}")
    if sbom[:status].success?
      return {found: true, source: "cosign .sbom tag (deprecated)", reason: nil}
    end
  end

  {found: false, source: nil, reason: nil}
end

desc "Do the CNF's container images have an SBOM (Software Bill of Materials) available?"
scored_task "sbom_available",
  type: CNFManager::TestType::Normal,
  emoji: "📋🔒" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    unless ClusterTools.install
      result.skipped("Skipping sbom_available: cluster-tools failed to install")
      next
    end

    checked_images = {} of String => NamedTuple(found: Bool?, source: String?, reason: String?)
    missing_sbom = [] of String
    unverifiable = [] of NamedTuple(kind: String, name: String, namespace: String, container: String?, image: String, reason: String?)
    inspected_targets = 0

    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _|
      # Only inspect pod-styled workload containers that declare an image.
      unless WORKLOAD_RESOURCE_KIND_NAMES.includes?(resource[:kind].downcase) && container.as_h["image"]?
        next true
      end

      image_url = container.as_h["image"].as_s
      fqdn_image = image_fqdn(image_url, config.common.image_registry_fqdns)
      inspected_targets += 1

      # Reuse a previous decision for a duplicate image.
      check = checked_images.fetch(fqdn_image) do
        checked_images[fqdn_image] = sbom_available_for_image?(fqdn_image)
      end

      case check[:found]
      when true
        result.append_description("SBOM for #{fqdn_image}: #{check[:source]}")
        true
      when false
        result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace],
          container: container.as_h["name"]?.try(&.as_s),
          reason: "no SBOM found for image #{fqdn_image}")
        missing_sbom << fqdn_image unless missing_sbom.includes?(fqdn_image)
        false
      else # nil: could not inspect the image — not a failure, just unverifiable
        result.append_description("#{fqdn_image}: #{check[:reason]}")
        unless unverifiable.any? { |u| u[:image] == fqdn_image }
          unverifiable << {kind: resource[:kind], name: resource[:name], namespace: resource[:namespace],
            container: container.as_h["name"]?.try(&.as_s), image: fqdn_image, reason: check[:reason]}
        end
        true # does not count against the test
      end
    end

    if inspected_targets == 0
      result.na("The CNF declares no container images; SBOM availability does not apply")
    elsif !missing_sbom.empty?
      result.append_remediation("Publish an SBOM for each container image — attach it with `docker buildx build --sbom=true` (an OCI attestation manifest with an SPDX or CycloneDX layer) or `cosign attest --type spdxjson` (a cosign attestation). The deprecated `cosign attach sbom` / `.sbom` tag is checked as a fallback.")
      result.failed("Found #{missing_sbom.size} container image(s) without a discoverable SBOM")
    elsif !unverifiable.empty?
      unverifiable.each do |u|
        result.add_impacted_resource(u[:kind], u[:name], u[:namespace],
          container: u[:container], reason: "image #{u[:image]}: #{u[:reason]}")
      end
      result.append_remediation("Ensure the registry is reachable and credentials are available so the test can inspect the images.")
      result.skipped("Could not verify #{unverifiable.size} container image(s) (network/registry auth)")
    else
      result.passed("An SBOM is available for every container image")
    end
  end
end

desc "Check that every workload of the CNF runs as a service account of its own, not the namespace's default"
scored_task "dedicated_service_account",
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    findings = [] of NamedTuple(kind: String, name: String, namespace: String, reason: String)
    judged = 0

    CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      live = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      pod_spec = live.dig?("spec", "template", "spec") || live.dig?("spec")
      judged += 1
      # The API server mirrors the deprecated serviceAccount field into
      # serviceAccountName, so a chart using either is judged by what it names.
      # An unset field stays empty on a pod template; on a bare Pod, admission
      # has already filled in "default".
      account = pod_spec.try(&.dig?("serviceAccountName")).try(&.as_s?).presence
      label = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}"
      if account.nil?
        findings << {kind: resource[:kind], name: resource[:name], namespace: resource[:namespace],
                     reason: "sets no serviceAccountName, so its pods run as the namespace's default service account"}
      elsif account == "default"
        findings << {kind: resource[:kind], name: resource[:name], namespace: resource[:namespace],
                     reason: "runs as the namespace's default service account"}
      else
        result.append_description("#{label}: service account #{account}")
      end
      true
    end

    if findings.empty?
      result.passed("All #{judged} workload(s) run as a service account other than default")
    else
      findings.each do |f|
        result.add_impacted_resource(f[:kind], f[:name], f[:namespace], reason: f[:reason])
      end
      result.append_remediation("Create a ServiceAccount for the workload in the CNF's chart and set serviceAccountName to it in the pod template, so its API permissions and audit trail are its own and not shared with every other pod using the default service account.")
      result.failed("Found #{findings.size} of #{judged} workload(s) running as the default service account")
    end
  end
end

desc "Check that the CNF's pods meet the Pod Security Standards baseline level, as judged by the API server"
scored_task "pod_security_baseline",
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # One pod per owner and spec: replicas share a verdict, pods that differ
    # (mid-rollout, or under an operator) are each judged.
    variants = {} of String => NamedTuple(pod: JSON::Any, namespace: String)
    CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      live = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      KubectlClient::Get.pods_by_resource_labels(live, resource[:namespace]).each do |pod|
        next if pod.dig?("metadata", "deletionTimestamp")
        next if pod.dig?("metadata", "annotations", "helm.sh/hook")
        variants[PodSecurity.variant_key(pod)] ||= {pod: pod, namespace: resource[:namespace]}
      end
      true
    end

    if variants.empty?
      result.append_remediation("Make sure the CNF's pods are running (a workload scaled to zero has none), then run the test again.")
      next result.skipped("No pod of the CNF could be read; the Pod Security baseline could not be checked")
    end

    version = KubectlClient.server_version rescue "unknown"
    PodSecurity.ensure_namespace
    findings = 0
    judged = 0
    not_judged = [] of String
    variants.each_value do |v|
      pod_name = v[:pod].dig?("metadata", "name").try(&.as_s?) || ""
      success, output = PodSecurity.dry_run(v[:pod])
      verdict, reason = PodSecurity.verdict(success, output)
      case verdict
      when PodSecurity::Verdict::Passed
        judged += 1
      when PodSecurity::Verdict::Violation
        judged += 1
        findings += 1
        result.add_impacted_resource("Pod", pod_name, v[:namespace],
          reason: "#{PodSecurity.owner(v[:pod])} violates Pod Security \"#{PodSecurity::LEVEL}\": #{reason}")
      else
        not_judged << "Pod/#{pod_name} in #{v[:namespace]} (#{PodSecurity.owner(v[:pod])}): not judged, the dry run was rejected by something other than Pod Security: #{reason}"
      end
    end
    not_judged.each { |line| result.append_description(line) }
    result.append_description("Judged at Pod Security \"#{PodSecurity::LEVEL}:latest\" of Kubernetes v#{version}")

    if findings > 0
      result.append_remediation("Bring each pod's spec within the Pod Security Standards baseline level: no host namespaces, privileged containers, hostPath volumes or host ports, only the baseline's allowed capabilities and sysctls, and the default /proc mount, AppArmor, SELinux and seccomp settings.")
      result.failed("Found #{findings} of #{judged} pod variant(s) of the CNF violating Pod Security \"#{PodSecurity::LEVEL}\"")
    elsif judged == 0
      result.append_remediation("See why the dry runs were rejected in the details; a validating webhook or quota on the cluster may need to allow the #{PodSecurity::BASELINE_NAMESPACE} namespace.")
      result.skipped("No pod of the CNF could be judged; every dry run was rejected by something other than Pod Security")
    else
      result.passed("All #{judged} pod variant(s) of the CNF meet Pod Security \"#{PodSecurity::LEVEL}\"")
    end
  end
end
