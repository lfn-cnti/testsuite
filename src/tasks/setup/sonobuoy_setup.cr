require "sam"
require "file_utils"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Sonobuoy in the K8s Cluster"
  task "install_sonobuoy" do |_, args|
    logger = SLOG.for("install_sonobuoy")
    logger.info { "Installing Sonobuoy tool" }
    failed_msg = "Task 'install_sonobuoy' failed"

    installed = ToolInstall.ensure("sonobuoy", SONOBUOY_K8S_VERSION, Setup::SONOBUOY_BINARY) do
      sonobuoy_archive = "#{Setup::SONOBUOY_DIR}/sonobuoy.tar.gz"
      begin
        download_file(Setup::SONOBUOY_URL, sonobuoy_archive)
      rescue ex : Exception
        logger.error { "Error while downloading sonobuoy binary: #{ex.message}" }
        next false
      end

      untar_result = TarClient.untar(sonobuoy_archive, Setup::SONOBUOY_DIR)
      File.delete(sonobuoy_archive) if File.exists?(sonobuoy_archive)
      unless untar_result[:status].success?
        logger.error { "Error while extracting sonobuoy archive: #{untar_result[:error]}" }
        next false
      end

      File.chmod(Setup::SONOBUOY_BINARY, 0o755)
      logger.info { "Sonobuoy tool has been installed" }
      true
    end
    stdout_failure(failed_msg) unless installed
  end

  desc "Uninstalls Sonobuoy"
  task "uninstall_sonobuoy" do |_, args|
    logger = SLOG.for("uninstall_sonobuoy")
    logger.info { "Uninstalling Sonobuoy tool" }

    unless File.exists?(Setup::SONOBUOY_BINARY)
      FileUtils.rm_rf(Setup::SONOBUOY_DIR)
      logger.info { "Sonobuoy tool has been uninstalled" }
      next
    end

    resp = ShellCmd.run("#{Setup::SONOBUOY_BINARY} delete --wait")
    unless resp[:status].success?
      logger.error { "Error while deleting sonobuoy from the cluster: #{resp[:error]}" }
      # Do not delete sonobuoy directory if it failed to delete itself from cluster,
      # user might want to repeat the deletion.
      stdout_failure("Task 'uninstall_sonobuoy' failed")
    else
      FileUtils.rm_rf(Setup::SONOBUOY_DIR)
      logger.info { "Sonobuoy tool has been uninstalled" }
    end
  end
end
