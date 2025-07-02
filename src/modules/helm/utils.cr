require "file_utils"
require "./constants.cr"
require "../tar"
require "../../tasks/setup/constants.cr"

module Helm
  struct Binary
    @@helm : String = ""

    # This will return path to helm binary if its found globally or installed by testsuite.
    # If helm is not found it will return empty string.
    def self.get : String
      return @@helm unless @@helm.empty?
      if Helm.global_helm?
        @@helm = "helm"
      else
        @@helm = Setup::HELM_BINARY if File.exists?(Setup::HELM_BINARY)
      end
      @@helm
    end
  end

  def self.install_local_helm : Bool
    logger = Log.for("install_local_helm")
    logger.info { "Installing Helm tool locally" }
    failed_msg = "Helm installation failed"

    FileUtils.mkdir_p(Setup::HELM_DIR)
    if File.exists?(Setup::HELM_BINARY)
      logger.notice { "Helm binary found in: #{Setup::HELM_BINARY}, skipping installation" }
      return true
    end

    begin
      helm_archive = "helm-#{Setup::HELM_VERSION}.tar.gz"
      download_file(Setup::HELM_URL, helm_archive)
    rescue ex : Exception
      logger.error { "Error while downloading Helm binary: #{ex.message}" }
      return false
    end

    unless (res = TarClient.untar(helm_archive, Setup::HELM_DIR))[:status].success?
      logger.error { "Error while extracting Helm binary: #{res[:error]}" }
      return false
    end

    true
  end

  def self.uninstall_local_helm
    logger = Log.for("uninstall_local_helm").info { "Unistalling Helm tool locally" }
    FileUtils.rm_rf(Setup::HELM_DIR)
  end

  def self.global_helm? : Bool
    ShellCMD.run("helm version", Log.for("global_helm_response"))[:status].success?
  end

  def self.helm_gives_k8s_warning? : {Bool, String?}
    logger = Log.for("helm_gives_k8s_warning?")
    helm = Binary.get

    begin
      resp = ShellCMD.raise_exc_on_error { ShellCMD.run("#{helm} list", logger) }
      # Helm version v3.3.3 gave us a surprise
      if (resp[:output] + resp[:error]) =~ /WARNING: Kubernetes configuration file is/
        return {true, "For this version of helm you must set your K8s config file permissions to chmod 700"}
      end

      {false, nil}
    rescue
      {true, "Please use newer version of helm"}
    end
  end
end
