require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/utils/mysql.cr"
require "kubectl_client"
require "helm"
require "file_utils"
require "sam"
require "json"

describe "Operator" do

  it "'operator_test' test if operator is being used", tags: ["operator_test"]  do
    current_dir = FileUtils.pwd
    install_dir = "#{tools_path}/olm"
    if Dir.exists?("#{install_dir}/olm/.git")
      Log.info { "OLM already installed. Skipping git clone for OLM." }
    else
      GitClient.clone("https://github.com/operator-framework/operator-lifecycle-manager.git #{install_dir}")
      result = ShellCmd.run("cd #{install_dir} && git fetch -a && git checkout tags/v0.22.0 && cd -")
    end

    Helm.install("operator", "#{install_dir}/deploy/chart/", values: "--set olm.image.ref=quay.io/operator-framework/olm:v0.22.0 --set catalog.image.ref=quay.io/operator-framework/olm:v0.22.0 --set package.image.ref=quay.io/operator-framework/olm:v0.22.0")

    begin
      ShellCmd.cnf_install("cnf-path=./sample-cnfs/sample_operator", cmd_prefix: "LOG_LEVEL=info")
      result = ShellCmd.run_testsuite("operator_installed", cmd_prefix: "LOG_LEVEL=info")
      (/(PASSED).*(Operator is installed)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall(cmd_prefix: "LOG_LEVEL=info")
      result[:status].success?.should be_true
      pods = KubectlClient::Get.pods_by_resource_labels(KubectlClient::Get.resource("deployment", "catalog-operator", "operator-lifecycle-manager"), "operator-lifecycle-manager") + 
        KubectlClient::Get.pods_by_resource_labels(KubectlClient::Get.resource("deployment", "olm-operator", "operator-lifecycle-manager"), "operator-lifecycle-manager") +
        KubectlClient::Get.pods_by_resource_labels(KubectlClient::Get.resource("deployment", "packageserver", "operator-lifecycle-manager"), "operator-lifecycle-manager")

      Helm.uninstall("operator")
      KubectlClient::Delete.resource("csv", "prometheusoperator.0.47.0")

      pods.map do |pod| 
        pod_name = pod.dig("metadata", "name")
        pod_namespace = pod.dig("metadata", "namespace")
        Log.info { "Wait for Uninstall on Pod Name: #{pod_name}, Namespace: #{pod_namespace}" }
        KubectlClient::Wait.resource_wait_for_uninstall("Pod", "#{pod_name}", 180, "operator-lifecycle-manager")
      end

      repeat_with_timeout(timeout: GENERIC_OPERATION_TIMEOUT, errormsg: "Namespace uninstallation has timed-out") do
        File.write("operator.json", "#{KubectlClient::Get.resource("namespace", "operators").to_json}")
        json = File.open("operator.json") do |file|
          JSON.parse(file)
        end
        json.as_h.delete("spec")
        File.write("operator.json", "#{json.to_json}")
        Log.info { "Uninstall Namespace Finalizer" }
        KubectlClient::Utils.replace_raw("'/api/v1/namespaces/operators/finalize'", "-f ./operator.json")[:status].success?
      end

      repeat_with_timeout(timeout: GENERIC_OPERATION_TIMEOUT, errormsg: "Namespace uninstallation has timed-out") do
        File.write("manager.json", "#{KubectlClient::Get.resource("namespace", "operator-lifecycle-manager").to_json}")
        json = File.open("manager.json") do |file|
          JSON.parse(file)
        end
        json.as_h.delete("spec")
        File.write("manager.json", "#{json.to_json}")
        Log.info { "Uninstall Namespace Finalizer" }
        KubectlClient::Utils.replace_raw("'/api/v1/namespaces/operator-lifecycle-manager/finalize'", "-f ./manager.json")[:status].success?
      end
    end
  end
  
  it "'operator_test' operator should not be found", tags: ["operator_test"]  do
    begin
      ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_coredns")
      result = ShellCmd.run_testsuite("operator_installed", cmd_prefix: "LOG_LEVEL=info")
      (/(N\/A).*(No Operators Found)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end
end
