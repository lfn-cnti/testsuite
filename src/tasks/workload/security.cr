# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "CNF containers should be isolated from one another and the host.  The CNF Test suite uses tools like Sysdig Inspect and gVisor"
task "security", [
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
  ] do |_, args|
  stdout_score("security")
  case "#{ARGV.join(" ")}" 
  when /security/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end

desc "Check if pods in the CNF use sysctls with restricted values"
task "sysctls" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    Kyverno.install
    policy_path = Kyverno.policy_path("pod-security/baseline/restrict-sysctls/restrict-sysctls.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)

    if failures.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No restricted values found for sysctls")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          puts "#{resource.kind} #{resource.name} in #{resource.namespace} namespace failed. #{failure.message}".colorize(:red)
        end
      end
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Restricted values for are being used for sysctls")
    end
  end
end

desc "Check if the CNF has services with external IPs configured"
task "external_ips" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    Kyverno.install
    policy_path = Kyverno.best_practice_policy("restrict-service-external-ips/restrict-service-external-ips.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

    resource_keys = CNFManager.resource_refs(args, config, ["service"]) do |service|
      "#{service[:namespace]},#{service[:kind]}/#{service[:name]}".downcase
    end    

    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)
    
    if failures.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Services are not using external IPs")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          puts "#{resource.kind} #{resource.name} in #{resource.namespace} namespace failed. #{failure.message}".colorize(:red)
        end
      end
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Services are using external IPs")
    end
  end
end

desc "Check if the CNF or the cluster resources have custom SELinux options"
task "selinux_options" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
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
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::NA, "Pods are not using SELinux")
    else
      failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, disallow_failures)

      if failures.size == 0
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Pods are not using custom SELinux options that can be used for privilege escalations")
      else
        failures.each do |failure|
          failure.resources.each do |resource|
            puts "#{resource.kind} #{resource.name} in #{resource.namespace} namespace failed. #{failure.message}".colorize(:red)
          end
        end
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Pods are using custom SELinux options that can be used for privilege escalations")
      end
    end
  end
end

desc "Check if the CNF is running containers with container sock mounts"
task "container_sock_mounts" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    Kyverno.install
    policy_path = Kyverno.best_practice_policy("disallow_cri_sock_mount/disallow_cri_sock_mount.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

    if failures.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Container engine daemon sockets are not mounted as volumes")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          puts "#{resource.kind} #{resource.name} in #{resource.namespace} namespace failed. #{failure.message}".colorize(:red)
        end
      end
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Container engine daemon sockets are mounted as volumes")
    end
  end
end

desc "Check if any containers are running in privileged mode"
task "privileged_containers" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    white_list_container_names = config.common.white_list_container_names
    Log.debug { "white_list_container_names #{white_list_container_names.inspect}" }
    violation_list = [] of NamedTuple(kind: String, name: String, container: String, namespace: String)
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _|
      privileged_list = KubectlClient::Get.privileged_containers(all_namespaces: true).map { |container| container.dig("name") }.uniq
      resource_containers = KubectlClient::Get.resource_containers(resource["kind"],resource["name"],resource["namespace"])
      resource_containers_list = resource_containers.as_a.map { |element| element["name"] }
      # Only check the containers that are in the deployed helm chart or manifest
      (privileged_list & (resource_containers_list - white_list_container_names)).each do |container_name|
        violation_list << {kind: resource["kind"], name: resource["name"], container: container_name.to_s, namespace: resource["namespace"]}
      end
      if violation_list.size > 0
        false
      else
        true
      end
    end
    Log.debug { "violator list: #{violation_list.flatten}" }
    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No privileged containers")
    else
      violation_list.each do |violation|
        stdout_failure("Privileged container #{violation[:container]} in #{violation[:kind]}/#{violation[:name]} in the #{violation[:namespace]} namespace")
      end
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found #{violation_list.size} privileged containers")
    end
  end
end

desc "Check if any containers are running in privileged mode"
task "privilege_escalation", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Allow privilege escalation")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No containers that allow privilege escalation were found")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers that allow privilege escalation")
    end
  end
end

desc "Check if an attacker can use symlink for arbitrary host file system access."
task "symlink_file_system", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "CVE-2021-25741 - Using symlink for arbitrary host file system access.")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No containers allow a symlink attack")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers that allow a symlink attack")
    end
  end
end

desc "Check if applications credentials are in configuration files."
task "application_credentials", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Applications credentials in configuration files")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No applications credentials in configuration files")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found applications credentials in configuration files")
    end
  end
end

desc "Check if potential attackers may gain access to a POD and inherit access to the entire host network. For example, in AWS case, they will have access to the entire VPC."
task "host_network", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "HostNetwork access")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No host network attached to pod")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found host network attached to pod")
    end
  end
end

desc "Potential attacker may gain access to a POD and steal its service account token. Therefore, it is recommended to disable automatic mapping of the service account tokens in service account configuration and enable it only for PODs that need to use them."
task "service_account_mapping", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Automatic mapping of service account")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.resource_refs(args, config, ["serviceAccount"]) do |serviceAccount|
      "#{serviceAccount[:namespace]},#{serviceAccount[:kind]}/#{serviceAccount[:name]}".downcase
    end.compact   
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No service accounts automatically mapped")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Service accounts automatically mapped")
    end
  end
end

desc "Check if security services are being used to harden the application"
task "linux_hardening", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Linux hardening")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Security services are being used to harden applications")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found resources that do not use security services")
    end
  end
end

desc "Check if the containers have insecure capabilities."
task "insecure_capabilities", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Insecure capabilities")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Containers with insecure capabilities were not found")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers with insecure capabilities")
    end
  end
end

desc "Check if the containers have CPU limits set"
task "cpu_limits", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Ensure CPU limits are set")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Containers have CPU limits set")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers without CPU limits set")
    end
  end
end

desc "Check if the containers have memory limits set"
task "memory_limits", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Ensure memory limits are set")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Containers have memory limits set")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers without memory limits set")
    end
  end
end

desc "Check Ingress and Egress traffic policy"
task "ingress_egress_blocked", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Ingress and Egress blocked")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Ingress and Egress traffic blocked on pods")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Ingress and Egress traffic not blocked on pods")
    end
  end
end

desc "Check the Host PID/IPC privileges of the containers"
task "host_pid_ipc_privileges", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Host PID/IPC privileges")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No containers with hostPID and hostIPC privileges")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers with hostPID and hostIPC privileges")
    end
  end
end

desc "Check if the containers are running with non-root user with non-root group membership"
task "non_root_containers", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Non-root containers")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Containers are running with non-root user with non-root group membership")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers running with root user or user with root group membership")
    end
  end
end

desc "Check if containers have immutable file systems"
task "immutable_file_systems", ["setup:kubescape_scan"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    results_json = Kubescape.parse
    test_json = Kubescape.test_by_test_name(results_json, "Immutable container filesystem")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Containers have immutable file systems")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers with mutable file systems")
    end
  end
end

desc "Check if containers have hostPath mounts"
task "hostpath_mounts", ["setup:install_kubescape"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    kubescape_control_id = "C-0048"
    Kubescape.scan(control_id: kubescape_control_id)
    results_file = Kubescape.control_results_file(kubescape_control_id)
    results_json = Kubescape.parse(results_file)
    test_json = Kubescape.test_by_test_name(results_json, "HostPath mount")
    test_report = Kubescape.parse_test_report(test_json)
    resource_keys = CNFManager.workload_resource_keys(args, config)
    test_report = Kubescape.filter_cnf_resources(test_report, resource_keys)

    if test_report.failed_resources.size == 0
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Containers do not have hostPath mounts")
    else
      test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
      stdout_failure("Remediation: #{test_report.remediation}")
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found containers with hostPath mounts")
    end
  end
end
