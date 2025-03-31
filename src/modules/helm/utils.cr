require "file_utils"
require "./constants.cr"
require "../tar"
require "../../tasks/setup/constants.cr"
require "../tool_checker.cr"

module Helm
  extend ToolChecker

  # ToolChecker hooks

  protected def self.tool_name : String
    "helm"
  end

  protected def self.global_check(result : ToolChecker::Result) : Nil
    cmd_result = ShellCMD.run("helm version", Log.for("global_helm_response"))

    if cmd_result[:status].success?
      result.global.path    = "helm"
      result.global.version = extract_version(cmd_result[:output] + cmd_result[:error])
    else
      result.warnings << "Global helm not found"
    end
  end

  protected def self.local_check(result : ToolChecker::Result) : Nil
    if File.exists?(Setup::HELM_BINARY)
      result.local.path = Setup::HELM_BINARY

      cmd_result = ShellCMD.run("#{Setup::HELM_BINARY} version", Log.for("local_helm_response"))
      if cmd_result[:status].success?
        result.local.version = extract_version(cmd_result[:output] + cmd_result[:error])
      else
        result.warnings << "Local helm binary present but failed to report version"
      end
    else
      result.warnings << "Local helm not found"
    end
  end

  protected def self.post_checks(result : ToolChecker::Result) : Nil
    helm_path = result.local.path || result.global.path
    return unless helm_path

    warning_message, error_message = helm_gives_k8s_warning?(helm_path)

    result.errors   << error_message   if error_message
    result.warnings << warning_message if warning_message
  end

  # Public helpers

  # Temporary solution for task prereqs/specs
  def self.installation_found? : Bool
    result = check

    # Global line
    if result.global_ok
      version_string = result.global.version || "unknown"
      stdout_success "Global helm found. Version: #{version_string}"
    end

    # Local line
    if result.local_ok
      version_string = result.local.version || "unknown"
      stdout_success "Local helm found. Version: #{version_string}"
    end

    # Extra info from post_checks
    result.errors.each   { |message| stdout_failure message }
    result.warnings.each { |message| stdout_warning  message }

    result.ok?
  end


  class Binary
    @@helm : String = ""

    # This will return path to helm binary if its found globally or installed by testsuite.
    # If helm is not found it will return empty string.
    def self.get : String
      return @@helm unless @@helm.empty?

      result = Helm.check
      if result.local_ok
        @@helm = result.local.path.not_nil!
      elsif result.global_ok
        @@helm = result.global.path.not_nil!
      else
        raise HelmBinaryNotFoundError.new
      end
    end

    class HelmBinaryNotFoundError < Exception
      def initialize
        super("No Helm binary found locally or globally.")
      end
    end
  end

  def self.install_local_helm : Bool
    logger = Log.for("install_local_helm")
    logger.info { "Installing Helm tool locally" }

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

  # Internals

  private def self.helm_gives_k8s_warning?(helm_path : String) : {String?, String?}
    logger = Log.for("helm_gives_k8s_warning?")
    begin
      resp      = ShellCMD.raise_exc_on_error { ShellCMD.run("#{helm_path} list", logger) }
      combined  = resp[:output] + resp[:error]

      if combined =~ /WARNING: Kubernetes configuration file is/
        return {"For this version of Helm you must set your K8s config file permissions to chmod 700", nil}
      end

      {nil, nil}
    rescue
      {nil, "Please use newer version of Helm"}
    end
  end

  private def self.extract_version(output : String) : String?
    output[/Version:"v?(\d+\.\d+\.\d+)"/, 1]?
  end
end
