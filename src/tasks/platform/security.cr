# coding: utf-8
require "sam"
require "colorize"
require "../utils/utils.cr"

namespace "platform" do
  desc "The CNF test suite checks to see if the platform is hardened."
  task "security", ["control_plane_hardening", "cluster_admin", "helm_tiller", "verify_configmaps_encryption"] do |t, args|
    Log.debug { "security" }
    stdout_score("platform:security")
  end

  desc "Is the platform control plane hardened"
  task "control_plane_hardening", ["kubescape_scan"] do |t, args|
    task_response = CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args|
      results_json = Kubescape.parse
      test_json = Kubescape.test_by_test_name(results_json, "API server insecure port is enabled")
      test_report = Kubescape.parse_test_report(test_json)

      if test_report.failed_resources.size == 0
        CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Passed, "Insecure port of Kubernetes API server is not enabled")
      else
        test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
        stdout_failure("Remediation: #{test_report.remediation}")
        CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "Insecure port of Kubernetes API server is enabled")
      end
    end
  end

  desc "Attackers who have Cluster-admin permissions (can perform any action on any resource), can take advantage of their high privileges for malicious intentions. Determines which subjects have cluster admin permissions."
  task "cluster_admin", ["kubescape_scan"] do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      results_json = Kubescape.parse
      test_json = Kubescape.test_by_test_name(results_json, "Administrative Roles")
      test_report = Kubescape.parse_test_report(test_json)

      if test_report.failed_resources.size == 0
        CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Passed, "No users with cluster-admin RBAC permissions were found")
      else
        test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
        stdout_failure("Remediation: #{test_report.remediation}")
        CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "Users with cluster-admin RBAC permissions found")
      end
    end
  end

  desc "Check if the CNF is running containers with name tiller in their image name?"
  task "helm_tiller" do |t, args|
    Kyverno.install
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      policy_path = Kyverno.best_practice_policy("disallow_helm_tiller/disallow_helm_tiller.yaml")
      failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

      if failures.size == 0
        CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Passed, "No Helm Tiller containers are running")
      else
        failures.each do |failure|
          failure.resources.each do |resource|
            puts "#{resource.kind} #{resource.name} in #{resource.namespace} namespace failed. #{failure.message}".colorize(:red)
          end
        end
        CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "Containers with the Helm Tiller image are running")
      end
    end
  end

  desc "Verify if configmaps are encrypted"
  task "verify_configmaps_encryption" do |t, args|
    kube_system_ns = "kube-system"
    cm_name = generate_cm_name
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      test_cm_key = "key"
      test_cm_value = "testconfigmapvalue"
      KubectlClient::Create.command("cm #{cm_name} --from-literal=#{test_cm_key}=#{test_cm_value}")
      etcd_pod_name = get_full_pod_name("etcd", kube_system_ns)
    
      if etcd_pod_name
        etcd_certs_path = get_etcd_certs_path(etcd_pod_name, kube_system_ns)
        if etcd_certs_path
          if etcd_cm_encrypted?(etcd_certs_path, etcd_pod_name, cm_name, test_cm_value, kube_system_ns)
            CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Passed, "Configmaps are encrypted in etcd")
          else
            CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "Configmaps are not encrypted in etcd")
          end
        else
          CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "Error: etcd certs path not found.")
        end
      else
        CNFManager::TestcaseResult.new(CNFManager::ResultStatus::Failed, "No etcd pod found.")
      end
    end
    KubectlClient::Delete.command("cm #{cm_name}")
  end
end
