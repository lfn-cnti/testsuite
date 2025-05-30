# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "Install LitmusChaos"
task "install_litmus" do |_, args|
  #todo in resilience node_drain task
  #todo get node name 
  #todo download litmus file then modify it with add_node_selector
  #todo apply modified litmus file
  Log.info { "install litmus" }
  begin 
    KubectlClient::Apply.namespace(LitmusManager::LITMUS_NAMESPACE)
  rescue ex: KubectlClient::ShellCMD::AlreadyExistsError
    Log.warn { "Cannot create #{LitmusManager::LITMUS_NAMESPACE}. Namespace already exists." }
  end
  cmd = "kubectl label namespace #{LitmusManager::LITMUS_NAMESPACE} pod-security.kubernetes.io/enforce=privileged"
  ShellCmd.run(cmd, "Label.namespace")
  Log.info { "install litmus operator"}
  KubectlClient::Apply.file(LitmusManager::LITMUS_OPERATOR, namespace: LitmusManager::LITMUS_NAMESPACE)
end

desc "Uninstall LitmusChaos"
task "uninstall_litmus" do |_, args|
  uninstall_chaosengine_cmd = "kubectl delete chaosengine --all --all-namespaces"
  status = Process.run(
      uninstall_chaosengine_cmd,
      shell: true,
      output: stdout = IO::Memory.new,
      error: stderr = IO::Memory.new
  )
  KubectlClient::AssureDeleted.file("https://litmuschaos.github.io/litmus/litmus-operator-v#{LitmusManager::Version}.yaml", namespace: LitmusManager::LITMUS_NAMESPACE)
  Log.info { stdout }
  Log.info { stderr }
end

module LitmusManager

  Version = "3.6.0"
  RBAC_VERSION = "2.6.0"
  # Version = "1.13.8"
  # Version = "3.0.0-beta12"
  NODE_LABEL = "kubernetes.io/hostname"
  #https://raw.githubusercontent.com/litmuschaos/chaos-operator/v2.14.x/deploy/operator.yaml
  LITMUS_OPERATOR = "https://litmuschaos.github.io/litmus/litmus-operator-v#{LitmusManager::Version}.yaml"
  # for node drain
  DOWNLOADED_LITMUS_FILE = "litmus-operator-downloaded.yaml"
  MODIFIED_LITMUS_FILE = "litmus-operator-modified.yaml"
  LITMUS_NAMESPACE = "litmus"
  LITMUS_K8S_DOMAIN = "litmuschaos.io"



  def self.add_node_selector(node_name)
    file = File.read(DOWNLOADED_LITMUS_FILE)
    deploy_index = file.index("kind: Deployment") || 0 
    spec_literal = "spec:"
    template = "\n      nodeSelector:\n        kubernetes.io/hostname: #{node_name}"
    spec1_index = file.index(spec_literal, deploy_index + 1)  || 0
    spec2_index = file.index(spec_literal, spec1_index + 1) || 0
    output_file = file.insert(spec2_index + spec_literal.size, template) unless spec2_index == 0
    File.write(MODIFIED_LITMUS_FILE, output_file) unless output_file == nil
  end

  def self.get_target_node_to_cordon(deployment_label, deployment_value, namespace)
    app_nodeName_cmd = "kubectl get pods -l #{deployment_label}=#{deployment_value} -n #{namespace} -o=jsonpath='{.items[0].spec.nodeName}'"
    Log.info { "Getting the operator node name: #{app_nodeName_cmd}" }
    status_code = Process.run("#{app_nodeName_cmd}", shell: true, output: appNodeName_response = IO::Memory.new, error: stderr = IO::Memory.new).exit_status
    Log.debug { "status_code: #{status_code}" } 
    appNodeName_response.to_s
  end

  private def self.get_status_info(chaos_resource, test_name, output_format, namespace) : {Int32, String}
    status_cmd = "kubectl get #{chaos_resource}.#{LITMUS_K8S_DOMAIN} #{test_name} -n #{namespace} -o '#{output_format}'"
    Log.info { "Getting litmus status info: #{status_cmd}" }
    status_code = Process.run("#{status_cmd}", shell: true, output: status_response = IO::Memory.new, error: stderr = IO::Memory.new).exit_status
    status_response = status_response.to_s
    Log.info { "status_code: #{status_code}, response: #{status_response}" }
    {status_code, status_response}
  end

  private def self.get_status_info_until(chaos_resource, test_name, output_format, timeout, namespace, &block)
    repeat_with_timeout(timeout: timeout, errormsg: "Litmus response timed-out") do
      status_code, status_response = get_status_info(chaos_resource, test_name, output_format, namespace)
      status_code == 0 && yield status_response
    end
  end

  ## wait_for_test will wait for the completion of litmus test
  def self.wait_for_test(test_name, chaos_experiment_name, args, namespace : String = "default")
    chaos_result_name = "#{test_name}-#{chaos_experiment_name}"
    Log.info { "wait_for_test: #{chaos_result_name}" }

    get_status_info_until("chaosengine", test_name, "jsonpath={.status.engineStatus}", LITMUS_CHAOS_TEST_TIMEOUT, namespace) do |engineStatus|
      ["completed", "stopped"].includes?(engineStatus)
    end

    get_status_info_until("chaosresults", chaos_result_name, "jsonpath={.status.experimentStatus.verdict}", GENERIC_OPERATION_TIMEOUT, namespace) do |verdict|
      verdict != "Awaited"
    end
  end

  ## check_chaos_verdict will check the verdict of chaosexperiment
  def self.check_chaos_verdict(chaos_result_name, chaos_experiment_name, args, namespace : String = "default") : Bool
    _, verdict = get_status_info("chaosresult", chaos_result_name, "jsonpath={.status.experimentStatus.verdict}", namespace)

    if verdict == "Pass"
      return true
    else
      Log.for("LitmusManager.check_chaos_verdict#details").debug do
        status_code, verdict_details_response = get_status_info("chaosresult", chaos_result_name, "json", namespace)
        "#{verdict_details_response}"
      end

      Log.for("LitmusManager.check_chaos_verdict").info {"#{chaos_experiment_name} chaos test failed: #{chaos_result_name}, verdict: #{verdict}"}
      return false
    end
  end

  def self.chaos_manifests_path
    Log.info {"chaos_manifests_path"}
    chaos_manifests = "#{tools_path}/chaos-experiments"
    if !Dir.exists?(chaos_manifests)
      FileUtils.mkdir_p(chaos_manifests)
    end
    chaos_manifests
  end

  def self.download_template(url, filename)
    Log.info {"download_template url, filename: #{url}, #{filename}"}
    cmp = chaos_manifests_path()
    filepath = "#{cmp}/#{filename}"
    Log.info {"filepath: #{filepath}"}

    download_file(url, filepath)

    filepath
  end
end
