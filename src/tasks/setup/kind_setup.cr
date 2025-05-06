require "sam"
require "file_utils"
require "../utils/utils.cr"

namespace "setup" do
  desc "Install Kind"
  task "install_kind" do |_, args|
    logger = SLOG.for("install_kind")
    logger.info { "Installing kind tool" }
    failed_msg = "Task 'install_kind' failed"

    if Dir.exists?(Setup::KIND_DIR)
      logger.notice { "kind directory: '#{Setup::KIND_DIR}' already exists, kind should be available" }
      next
    end

    FileUtils.mkdir_p(Setup::KIND_DIR)
    kind_binary = "#{Setup::KIND_DIR}/kind"

    begin
      download(Setup::KIND_DOWNLOAD_URL, kind_binary)
    rescue ex : Exception
      logger.error { "Error while downloading kind binary: #{ex.message}" }
      stdout_failure(failed_msg)
      exit(1)
    end
    logger.debug { "Downloaded kind binary" }

    unless ShellCmd.run("chmod +x #{kind_binary}")[:status].success?
      logger.error { "Error while making kind binary: '#{kind_binary}' executable" }
      stdout_failure(failed_msg)
      exit(1)
    end
    logger.info { "Kind tool has been installed" }
  end

  desc "Uninstall Kind"
  task "uninstall_kind" do |_, args|
    logger = SLOG.for("uninstall_kind").info { "Uninstall kind tool" }
    FileUtils.rm_rf(Setup::KIND_DIR)
  end
end