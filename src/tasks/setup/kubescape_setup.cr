require "sam"
require "file_utils"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Kubescape in the K8s Cluster"
  task "install_kubescape", ["setup:kubescape_framework_download"] do |_, args|
    logger = SLOG.for("install_kubescape")
    logger.info { "Installing Kubescape tool" }
    failed_msg = "Task 'install_kubescape' failed"

    ToolInstall.ensure("kubescape", Setup::KUBESCAPE_VERSION, Setup::KUBESCAPE_BINARY) do
      tarball = "#{Setup::KUBESCAPE_DIR}/kubescape.tar.gz"
      begin
        download_file(Setup::KUBESCAPE_URL, tarball)
      rescue ex : Exception
        logger.error { "Error while downloading kubescape tool: #{ex.message}" }
        stdout_failure(failed_msg)
        exit(1)
      end
      logger.debug { "Downloaded Kubescape tarball" }

      unless TarClient.untar(tarball, Setup::KUBESCAPE_DIR)[:status].success?
        logger.error { "Error while extracting kubescape tarball: '#{tarball}'" }
        stdout_failure(failed_msg)
        exit(1)
      end
      File.delete(tarball)
      logger.info { "Kubescape tool has been installed" }
      true
    end
  end

  desc "Kubescape framework download"
  task "kubescape_framework_download" do |_, args|
    logger = SLOG.for("kubescape_framework_download")
    logger.info { "Downloading Kubescape testing framework" }
    failed_msg = "Task 'kubescape_framework_download' failed"

    framework_path = "#{Setup::KUBESCAPE_DIR}/nsa.json"
    ToolInstall.ensure("kubescape NSA framework", Setup::KUBESCAPE_FRAMEWORK_VERSION, framework_path) do
      begin
        if ENV.has_key?("GITHUB_TOKEN")
          download_file(Setup::KUBESCAPE_FRAMEWORK_URL, framework_path,
            headers: HTTP::Headers{"Authorization" => "Bearer #{ENV["GITHUB_TOKEN"]}"})
        else
          download_file(Setup::KUBESCAPE_FRAMEWORK_URL, framework_path)
        end
      rescue ex : Exception
        logger.error { "Error while downloading kubescape framework: #{ex.message}" }
        stdout_failure(failed_msg)
        exit(1)
      end
      logger.info { "Kubescape framework json has been downloaded" }
      true
    end
  end

  desc "Kubescape Scan"
  task "kubescape_scan", ["setup:install_kubescape"] do |_, args|
    logger = SLOG.for("kubescape_scan").info { "Perform Kubescape cluster scan" }
    Kubescape.scan
  end

  desc "Uninstall Kubescape"
  task "uninstall_kubescape" do |_, args|
    logger = SLOG.for("setup:uninstall_kubescape").info { "Uninstall kubescape tool" }
    FileUtils.rm_rf(Setup::KUBESCAPE_DIR)
  end
end
