require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "Sets up OPA in the K8s Cluster"
task "install_opa", ["setup:install_local_helm", "setup:create_namespace"] do |_, args|
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

  StatusLine.push "Installing OPA Gatekeeper into the cluster..."
  Helm.helm_repo_add("gatekeeper", "https://open-policy-agent.github.io/gatekeeper/charts")
  begin
    Helm.install("opa-gatekeeper", "gatekeeper/gatekeeper", values: "--version #{Setup::GATEKEEPER_VERSION} #{helm_install_args}")
  rescue e : Helm::ShellCMD::CannotReuseReleaseNameError
    stdout_warning "gatekeeper already installed"
  end

  FileUtils.mkdir_p(Setup::RENDERED_MANIFESTS_DIR)
  enforce_manifest = File.join(Setup::RENDERED_MANIFESTS_DIR, "enforce-image-tag.yml")
  template_manifest = File.join(Setup::RENDERED_MANIFESTS_DIR, "constraint_template.yml")
  File.write(enforce_manifest, ENFORCE_IMAGE_TAG)
  File.write(template_manifest, CONSTRAINT_TEMPLATE)
  KubectlClient::Wait.wait_for_install_by_apply(template_manifest)
  # Gatekeeper generates the constraint CRD from the template asynchronously.
  # `kubectl wait` fails at once when the resource does not exist yet, so poll
  # until the CRD appears and is Established before creating a constraint.
  unless KubectlClient::Wait.wait_for_resource_availability("customresourcedefinition", "requiretags.constraints.gatekeeper.sh", nil, 300)
    raise "Gatekeeper did not create the requiretags constraint CRD within 300 seconds"
  end
  KubectlClient::Apply.file(enforce_manifest)
  StatusLine.pop
end

desc "Uninstall OPA"
task "uninstall_opa" do |_, args|
  Log.debug { "uninstall_opa" }
  enforce_manifest = File.join(Setup::RENDERED_MANIFESTS_DIR, "enforce-image-tag.yml")
  template_manifest = File.join(Setup::RENDERED_MANIFESTS_DIR, "constraint_template.yml")
  begin Helm.uninstall("opa-gatekeeper", TESTSUITE_NAMESPACE) rescue Helm::ShellCMD::ReleaseNotFound end
  begin KubectlClient::Delete.file(enforce_manifest) rescue KubectlClient::ShellCMD::NotFoundError end
  begin KubectlClient::Delete.file(template_manifest) rescue KubectlClient::ShellCMD::NotFoundError end
end
