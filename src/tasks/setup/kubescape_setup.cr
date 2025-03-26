require "sam"
require "file_utils"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up Kubescape in the K8s Cluster"
  task "install_kubescape", ["setup:kubescape_framework_download"] do |_, args|
    logger = SLOG.for("install_kubescape")
    logger.info { "Installing Kubescape tool" }
    failed_msg = "Task 'install_kubescape' failed"

    FileUtils.mkdir_p(Setup::KUBESCAPE_DIR)
    version_file = "#{Setup::KUBESCAPE_DIR}/.kubescape_version"
    installed_kubescape_version = File.read(version_file) if File.exists?(version_file)
    if File.exists?("#{Setup::KUBESCAPE_DIR}/kubescape") && installed_kubescape_version == Setup::KUBESCAPE_VERSION
      logger.info { "Kubescape tool already exists and has the required version" }
      next
    end

    kubescape_binary = "#{Setup::KUBESCAPE_DIR}/kubescape"
    begin
      download_file(Setup::KUBESCAPE_URL, kubescape_binary)
    rescue ex : Exception
      logger.error { "Error while downloading kubescape tool: #{ex.message}" }
      stdout_failure(failed_msg)
      exit(1)
    end
    logger.debug { "Downloaded Kubescape binary" }
    File.write(version_file, Setup::KUBESCAPE_VERSION)

    unless ShellCmd.run("chmod +x #{kubescape_binary}")[:status].success?
      logger.error { "Error while making kubescape binary: '#{kubescape_binary}' executable" }
      stdout_failure(failed_msg)
      exit(1)
    end

    logger.info { "Kubescape tool has been installed" }
  end

  desc "Kubescape framework download"
  task "kubescape_framework_download" do |_, args|
    logger = SLOG.for("kubescape_framework_download")
    logger.info { "Downloading Kubescape testing framework" }
    failed_msg = "Task 'kubescape_framework_download' failed"

    FileUtils.mkdir_p(Setup::KUBESCAPE_DIR)
    version_file = "#{Setup::KUBESCAPE_DIR}/.kubescape_framework_version"
    installed_framework_version = File.read(version_file) if File.exists?(version_file)

    framework_path = "#{tools_path}/kubescape/nsa.json"
    if File.exists?("#{Setup::KUBESCAPE_DIR}/nsa.json") &&
       installed_framework_version == Setup::KUBESCAPE_FRAMEWORK_VERSION
      logger.info { "Kubescape framework file already exists and has the required version" }
      next
    end

    begin
      if ENV.has_key?("GITHUB_TOKEN")
        download_file(Setup::KUBESCAPE_FRAMEWORK_URL, framework_path,
          headers: HTTP::Headers{"Authorization" => "Bearer #{ENV["GITHUB_TOKEN"]}"})
      else
        download_file(Setup::KUBESCAPE_FRAMEWORK_URL, framework_path)
      end
      logger.debug { "Downloaded Kubescape framework json" }
      File.write(version_file, Setup::KUBESCAPE_FRAMEWORK_VERSION)
    rescue ex : Exception
      logger.error { "Error while downloading kubescape framework: #{ex.message}" }
      stdout_failure(failed_msg)
      exit(1)
    end

    logger.info { "Kubescape framework json has been downloaded" }
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
