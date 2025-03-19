require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../modules/helm"

task "prereqs" do |_, args|
  helm_ok = Helm::SystemInfo.helm_installation_info() && begin
    warning, error = Helm.helm_gives_k8s_warning?
    stdout_failure(error) if !error.nil?
    !warning
  end
  kubectl_ok = KubectlClient.installation_found?()
  git_ok = GitClient.installation_found?

  checks = [
    helm_ok,
    kubectl_ok,
    git_ok
  ]

  if checks.includes?(false)
    stdout_failure "Dependency installation failed. Some prerequisites are missing. Please install all of the prerequisites before continuing."
    exit 1
  else
    stdout_success "All prerequisites found."
  end
end
