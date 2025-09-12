require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../../modules/helm"

namespace "setup" do
  task "prereqs" do |_, args|
    kubectl_ok = KubectlClient.installation_found?
    helm_ok = Helm.installation_found?
    git_ok = GitClient.installation_found?

    if [helm_ok, kubectl_ok, git_ok].includes?(false)
      stdout_failure "Dependency installation failed. Some prerequisites are missing. Please install all of the " +
                     "prerequisites before continuing."
      exit(1)
    else
      stdout_success "All prerequisites found."
    end
  end
end
