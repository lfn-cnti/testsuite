require "sam"
require "file_utils"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Sonobuoy in the K8s Cluster"
  task "install_sonobuoy" do |_, args|
    logger = SLOG.for("install_sonobuoy")
    logger.info { "Installing Sonobuoy tool" }
    failed_msg = "Task 'install_sonobuoy' failed"

    if Dir.exists?(SONOBUOY_DIR)
      logger.notice { "Sonobuoy directory: '#{SONOBUOY_DIR}' already exists, sonobuoy should be available" }
      next
    end

    FileUtils.mkdir_p(SONOBUOY_DIR)
    sonobuoy_archive = "#{SONOBUOY_DIR}/sonobuoy.tar.gz"
    begin
      download(SONOBUOY_URL, sonobuoy_archive)
    rescue ex : Exception
      logger.error { "Error while downloading sonobuoy binary: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end

    result = TarClient.untar(sonobuoy_archive, SONOBUOY_DIR)
    unless ShellCmd.run("chmod +x #{SONOBUOY_BINARY}")[:status].success?
      logger.error { "Error while making sonobuoy binary: '#{SONOBUOY_BINARY}' executable" }
      stdout_failure(failed_msg)
      next
    end
    # (rafal-lal) TODO: this rm cmd was here to delete archive after extracting binary, sounds good to add everywhere
    # rm #{tools_path}/sonobuoy/sonobuoy.tar.gz
    logger.info { "Sonobuoy tool has been installed" }
  end

  desc "Uninstalls Sonobuoy"
  task "uninstall_sonobuoy" do |_, args|
    logger = SLOG.for("uninstall_sonobuoy")
    logger.info { "Uninstalling Sonobuoy tool" }

    resp = ShellCmd.run("#{SONOBUOY_BINARY} delete --wait 2>&1")
    unless resp[:status].success?
      logger.error { "Error while deleting sonobuoy from the cluster: #{resp[:error]}" }
      # Do not delete sonobuoy directory if it failed to delete itself from cluster, user might want to repeat deletion.
      stdout_failure("Task 'uninstall_sonobuoy' failed")
    else
      FileUtils.rm_rf(SONOBUOY_DIR)
      logger.info { "Sonobuoy tool has been uninstalled" }
    end
  end
end
