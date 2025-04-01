require "sam"
require "file_utils"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Kubescape in the K8s Cluster"
  task "install_kubescape", ["kubescape_framework_download"] do |_, args|
    logger = SLOG.for("install_kubescape")
    logger.info { "Installing Kubescape tool" }
    failed_msg = "Task 'install_kubescape' failed"

    FileUtils.mkdir_p(KUBESCAPE_DIR)
    version_file = "#{KUBESCAPE_DIR}/.kubescape_version"
    installed_kubescape_version = File.read(version_file)
    if File.exists?("#{KUBESCAPE_DIR}/kubescape") && installed_kubescape_version == KUBESCAPE_VERSION
      logger.info { "Kubescape tool already exists and has the required version" }
      next
    end

    kubescape_binary = "#{KUBESCAPE_DIR}/kubescape"
    begin
      download(KUBESCAPE_URL, kubescape_binary)
    rescue ex : Exception
      logger.error { "Error while downloading kubescape tool: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end
    logger.debug { "Downloaded Kubescape binary" }
    File.write(installed_kubescape_version, KUBESCAPE_VERSION)

    unless ShellCmd.run("chmod +x #{kubescape_binary}")[:status].success?
      logger.error { "Error while making kubescape binary: '#{kubescape_binary}' executable" }
      stdout_failure(failed_msg)
      next
    end

    logger.info { "Kubescape tool has been installed" }
  end

  desc "Kubescape framework download"
  task "download_kubescape_framework" do |_, args|
    logger = SLOG.for("download_kubescape_framework")
    logger.info { "Downloading Kubescape testing framework" }
    failed_msg = "Task 'download_kubescape_framework' failed"

    FileUtils.mkdir_p(KUBESCAPE_DIR)
    version_file = "#{KUBESCAPE_DIR}/.kubescape_framework_version"
    installed_framework_version = File.read(version_file)

    framework_path = "#{tools_path}/kubescape/nsa.json"
    if File.exists?("#{KUBESCAPE_DIR}/nsa.json") && installed_framework_version == KUBESCAPE_FRAMEWORK_VERSION
      logger.info { "Kubescape framework file already exists and has the required version" }
      next
    end

    # (rafal-lal) TODO: what is the history of this TOKEN usage, is it still needed?
    begin
      if ENV.has_key?("GITHUB_TOKEN")
        download(KUBESCAPE_URL, framework_path,
          headers: HTTP::Headers{"Authorization" => "Bearer #{ENV["GITHUB_TOKEN"]}"})
      else
        download(KUBESCAPE_URL, framework_path)
      end
      logger.debug { "Downloaded Kubescape framework json" }
      File.write(version_file, KUBESCAPE_FRAMEWORK_VERSION)
    rescue ex : Exception
      logger.error { "Error while downloading kubescape framework: #{ex.message}" }
      stdout_failure(failed_msg)
      next
    end

    logger.info { "Kubescape framework json has been downloaded" }
  end

  desc "Kubescape Scan"
  task "kubescape_scan", ["install_kubescape"] do |_, args|
    logger = SLOG.for("kubescape_scan").info { "Perform Kubescape cluster scan" }
    Kubescape.scan
  end

  desc "Uninstall Kubescape"
  task "uninstall_kubescape" do |_, args|
    logger = SLOG.for("uninstall_kubescape").info { "Uninstall kubescape tool" }
    FileUtils.rm_rf(KUBESCAPE_DIR)
  end
end
