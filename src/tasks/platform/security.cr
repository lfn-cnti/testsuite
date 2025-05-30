# coding: utf-8
require "sam"
require "colorize"
require "../utils/utils.cr"
require "yaml"

namespace "platform" do
  desc "The CNF test suite checks to see if the platform is hardened."
  task "security", ["control_plane_hardening", "cluster_admin", "helm_tiller", "verify_configmaps_encryption", "verify_secrets_encryption"] do |t, args|
    Log.debug { "security" }
    stdout_score("platform:security")
  end

  desc "Is the platform control plane hardened"
  task "control_plane_hardening", ["setup:kubescape_scan"] do |t, args|
    task_response = CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args|
      results_json = Kubescape.parse
      test_json = Kubescape.test_by_test_name(results_json, "API server insecure port is enabled")
      test_report = Kubescape.parse_test_report(test_json)

      if test_report.failed_resources.size == 0
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Insecure port of Kubernetes API server is not enabled")
      else
        test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
        stdout_failure("Remediation: #{test_report.remediation}")
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Insecure port of Kubernetes API server is enabled")
      end
    end
  end

  desc "Attackers who have Cluster-admin permissions (can perform any action on any resource), can take advantage of their high privileges for malicious intentions. Determines which subjects have cluster admin permissions."
  task "cluster_admin", ["setup:kubescape_scan"] do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      results_json = Kubescape.parse
      test_json = Kubescape.test_by_test_name(results_json, "Administrative Roles")
      test_report = Kubescape.parse_test_report(test_json)

      if test_report.failed_resources.size == 0
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No users with cluster-admin RBAC permissions were found")
      else
        test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
        stdout_failure("Remediation: #{test_report.remediation}")
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Users with cluster-admin RBAC permissions found")
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
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No Helm Tiller containers are running")
      else
        failures.each do |failure|
          failure.resources.each do |resource|
            puts "#{resource.kind} #{resource.name} in #{resource.namespace} namespace failed. #{failure.message}".colorize(:red)
          end
        end
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Containers with the Helm Tiller image are running")
      end
    end
  end

  desc "Verify if ConfigMaps are encrypted"
  task "verify_configmaps_encryption" do |t, args|
    logger = Log.for("verify_configmaps_encryption")
    kube_system_ns = "kube-system"
    cm_name = generate_cm_name

    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      test_cm_key = "key"
      test_cm_value = "testconfigmapvalue"
      create_test_configmap(cm_name, test_cm_key, test_cm_value)
      
      etcd_pod_name = KubectlClient::Get.match_pods_by_prefix("etcd", namespace: kube_system_ns).first

      etcd_certs_path = get_etcd_certs_path(etcd_pod_name, kube_system_ns)
      
      if etcd_certs_path
        if etcd_cm_encrypted?(etcd_certs_path, etcd_pod_name, cm_name, test_cm_value, kube_system_ns)
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "ConfigMaps are encrypted in etcd.")
        else
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "ConfigMaps are not encrypted in etcd.")
        end
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Error: etcd certs path not found.")
      end
    end

    KubectlClient::AssureDeleted.resource("cm", cm_name)
  end
end

  private def generate_cm_name(prefix : String = "test-cm-") : String
    "#{prefix}-#{Random::Secure.rand(9999).to_s}"
  end

  private def create_test_configmap(cm_name : String, key : String, value : String) : Bool
    logger = Log.for("create_test_configmap")

    cm_manifest = <<-YAML
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: #{cm_name}
      data:
        #{key}: "#{value}"
    YAML

      file = File.tempfile("configmap", ".yaml")
      file.puts cm_manifest
      file.flush

      KubectlClient::Apply.file(file.path)
      
      file.delete
      return true
  end


  private def get_etcd_certs_path(etcd_pod_name : String, namespace : String) : String?
    logger = Log.for("get_etcd_certs_path")

    begin
      pod_info = KubectlClient::Get.resource("pod", etcd_pod_name, namespace: namespace)
      volumes_json = pod_info.dig?("spec", "volumes")
    
      volumes = volumes_json.try(&.as_a) rescue nil
    
      if volumes
        etcd_certs_volume = volumes.find { |volume| volume["name"]?.try(&.to_s) == "etcd-certs" }
    
        if etcd_certs_volume
          return etcd_certs_volume["hostPath"]?.try(&.["path"]?.to_s)
        else
          logger.warn { "No volume named 'etcd-certs' found in pod #{etcd_pod_name}" }
          return nil
        end
      else
        logger.warn { "No volumes array found in pod spec for #{etcd_pod_name}" }
        return nil
      end
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error { "Failed to get pod definition for #{etcd_pod_name}: #{ex.message}" }
      raise ex
    end
  end
 
  private def etcd_cm_encrypted?(
    etcd_certs_path : String, 
    etcd_pod_name : String, 
    cm_name : String, 
    test_cm_value : String, 
    namespace : String,
    ) : Bool
    etcd_output =  execute_etcd_command(etcd_certs_path, etcd_pod_name, cm_name, namespace)
    etcd_output.includes?("k8s:enc:") && !etcd_output.includes?(test_cm_value)
  end
  
  private def execute_etcd_command(etcd_certs_path : String, etcd_pod_name : String, cm_name : String, namespace : String) : String
    logger = Log.for("execute_etcd_command")

    command = "ETCDCTL_API=3 etcdctl " \
              "--cacert #{etcd_certs_path}/ca.crt " \
              "--cert #{etcd_certs_path}/server.crt " \
              "--key #{etcd_certs_path}/server.key " \
              "get /registry/configmaps/default/#{cm_name}"

    begin
      result = KubectlClient::Utils.exec(etcd_pod_name, "sh -c \"#{command}\"", namespace: namespace)
      result["output"]
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      logger.error {"Failed to execute etcdctl command in pod #{etcd_pod_name}: #{ex.message}"}
      raise ex 
    end
  end

  desc "Verify if Secrets are encrypted"
  task "verify_secrets_encryption", ["kubescape_scan"] do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      namespace="kube-system"
      Kubescape.scan(namespace: namespace)
      results_json = Kubescape.parse("kubescape_results.json")
      test_json = Kubescape.test_by_test_name(results_json, "Secret/etcd encryption enabled")
      test_report = Kubescape.parse_test_report(test_json)

      if test_report.failed_resources.size == 0
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Secret/etcd encryption enabled.")
      else
        test_report.failed_resources.map {|r| stdout_failure(r.alert_message) }
        stdout_failure("Remediation: #{test_report.remediation}")
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Secret/etcd encryption disabled.")
      end
    end
  end

