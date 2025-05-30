require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "Sets up OPA in the K8s Cluster"
task "install_opa", ["setup:helm_local_install", "setup:create_namespace"] do |_, args|
  helm_install_args_list = [
    "--set auditInterval=1",
    "--set postInstall.labelNamespace.enabled=false",
    "-n #{TESTSUITE_NAMESPACE}"
  ]

  k8s_server_version = KubectlClient.server_version
  if !version_less_than(k8s_server_version, "1.25.0")
    helm_install_args_list.push("--set psp.enabled=false")
  end

  helm_install_args = helm_install_args_list.join(" ")

  Helm.helm_repo_add("gatekeeper", "https://open-policy-agent.github.io/gatekeeper/charts")
  begin
    Helm.install("opa-gatekeeper", "gatekeeper/gatekeeper", values: helm_install_args)
  rescue e : Helm::ShellCMD::CannotReuseReleaseNameError
    stdout_warning "gatekeeper already installed"
  end

  File.write("enforce-image-tag.yml", ENFORCE_IMAGE_TAG)
  File.write("constraint_template.yml", CONSTRAINT_TEMPLATE)
  KubectlClient::Wait.wait_for_install_by_apply("constraint_template.yml")
  KubectlClient::Wait.wait_for_condition("crd", "requiretags.constraints.gatekeeper.sh", "condition=established", 300)
  KubectlClient::Apply.file("enforce-image-tag.yml")
end

desc "Uninstall OPA"
task "uninstall_opa" do |_, args|
  Log.debug { "uninstall_opa" }
  begin Helm.uninstall("opa-gatekeeper", TESTSUITE_NAMESPACE) rescue Helm::ShellCMD::ReleaseNotFound end
  KubectlClient::AssureDeleted.file("enforce-image-tag.yml")
  KubectlClient::AssureDeleted.file("constraint_template.yml")
  
end
