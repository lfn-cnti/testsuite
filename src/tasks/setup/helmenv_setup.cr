require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "http/client"

def helm_arch
  "linux-amd64"
end

def helm_local_install_dir
  "#{tools_path}/helm/#{helm_arch}"
end

# This env var is to ensure that the helm shard is aware of the local helm.
#
# TODO: Instead of requiring this env var to be set,
# refactor the helm shard to use instance-based helpers instead of class methods.
ENV["CUSTOM_HELM_PATH"] = "#{helm_local_install_dir}/helm"

desc "Sets up helm 3.8.2"
task "helm_local_install", ["setup:cnf_directory_setup"] do |_, args|
  Log.debug { "helm_local_install" }
  # check if helm is installed
  # if proper version of helm installed, don't install
  if Helm::SystemInfo.global_helm_installed? && !ENV.has_key?("force_install")
    Log.info { "Globally installed helm satisfies required version. Skipping local helm install." }
  else
    current_dir = FileUtils.pwd
    Log.trace { current_dir }
    arch = "linux-amd64"

    FileUtils.mkdir_p("#{tools_path}/helm")
    unless File.exists?("#{helm_local_install_dir}/helm")
      begin       
        Log.trace { "full path?: #{tools_path}/helm" }

        download_file("https://get.helm.sh/helm-v3.8.2-#{helm_arch}.tar.gz","#{tools_path}/helm/helm-v3.8.2-#{helm_arch}.tar.gz")

        TarClient.untar(
          "#{tools_path}/helm/helm-v3.8.2-#{helm_arch}.tar.gz",
          "#{tools_path}/helm"
        )

        helm = Helm::BinarySingleton.helm
        stdout = IO::Memory.new
        status = Process.run("#{helm} version", shell: true, output: stdout, error: stdout)
        Log.trace { stdout }

        #TODO what is this for?
        stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
        Log.trace { "stable repo add: #{stable_repo}" }

        #TODO grep for specific version e.g. version.BuildInfo{Version:"v3.1.1", GitCommit:"afe70585407b420d0097d07b21c47dc511525ac8", GitTreeState:"clean", GoVersion:"go1.13.8"} 
      end
    end
  end
  # `#{Helm::BinarySingleton.helm} repo add stable https://cncf.gitlab.io/stable`
end

desc "Cleans up helm 3.8.2"
task "uninstall_local_helm" do |_, args|
  Log.debug { "uninstall_local_helm" }
  current_dir = FileUtils.pwd 
  FileUtils.rm_rf("#{tools_path}/helm")
end
