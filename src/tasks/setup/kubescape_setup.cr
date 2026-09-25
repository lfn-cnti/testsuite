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

    # The single-control scans used to let kubescape fetch the control from
    # the internet on every run; a failed fetch left an empty results file
    # and an errored test. The allcontrols framework (every control with its
    # rules) is downloaded once, with the NSA framework's version, and a
    # single-control scan takes its control from it.
    ToolInstall.ensure("kubescape allcontrols framework", Setup::KUBESCAPE_FRAMEWORK_VERSION, Kubescape::CONTROLS_FILE) do
      begin
        if ENV.has_key?("GITHUB_TOKEN")
          download_file(Setup::KUBESCAPE_CONTROLS_URL, Kubescape::CONTROLS_FILE,
            headers: HTTP::Headers{"Authorization" => "Bearer #{ENV["GITHUB_TOKEN"]}"})
        else
          download_file(Setup::KUBESCAPE_CONTROLS_URL, Kubescape::CONTROLS_FILE)
        end
      rescue ex : Exception
        logger.error { "Error while downloading kubescape allcontrols framework: #{ex.message}" }
        stdout_failure(failed_msg)
        exit(1)
      end
      logger.info { "Kubescape allcontrols framework json has been downloaded" }
      true
    end
  end

  desc "Kubescape Scan"
  task "kubescape_scan", ["setup:install_kubescape"] do |_, args|
    logger = SLOG.for("kubescape_scan")
    logger.info { "Perform Kubescape cluster scan" }
    begin
      Kubescape.scan
    rescue ex : Kubescape::ScanError
      # The tests that depend on this scan find no results file and report
      # the same reason as an error, one per test, instead of a stack trace.
      logger.error { ex.message }
      stdout_failure("Kubescape scan failed: #{ex.message}")
    end
  end

  desc "Uninstall Kubescape"
  task "uninstall_kubescape" do |_, args|
    logger = SLOG.for("setup:uninstall_kubescape").info { "Uninstall kubescape tool" }
    FileUtils.rm_rf(Setup::KUBESCAPE_DIR)
  end
end
