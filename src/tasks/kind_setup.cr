require "sam"
require "file_utils"
require "colorize"
require "totem"
require "./utils/utils.cr"
require "retriable"

private KIND_DIR = "#{tools_path}/kind"

namespace "setup" do
  desc "Install Kind"
  task "install_kind" do |_, args|
    logger = SLOG.for("install_kind")
    logger.info { "Installing kind tool" }

    current_dir = FileUtils.pwd
    if Dir.exists?(KIND_DIR)
      logger.notice { "kind directory: '#{KIND_DIR}' already exists, kind should be available" }
      next
    end

    FileUtils.mkdir_p(KIND_DIR)
    kind_binary = "#{KIND_DIR}/kind"

    begin
      HttpHelper.download(KIND_DOWNLOAD_URL, kind_binary).raise_for_status
    rescue ex : Halite::ClientError | Halite::ServerError
      logger.error { "Error while downloading kind binary: [#{ex.status_code}] #{ex.status_message}" }
      stdout_error("Task 'install_kind' failed")
      # (rafal-lal) TODO: SAM tasks error handling, what to do if prerequisite, setup task like this one fails?
      next
    end

    resp = ShellCmd.run("chmod +x #{kind_binary}")
    unless resp[:status].success?
      logger.error { "Error while making kind binary: '#{kind_binary}' executable" }
      stdout_error("Task 'install_kind' failed")
      # (rafal-lal) TODO: SAM tasks error handling, what to do if prerequisite, setup task like this one fails?
      next
    end
    logger.info { "Kind tool has been installed" }
  end

  desc "Uninstall Kind"
  task "uninstall_kind" do |_, args|
    logger = SLOG.for("uninstall_kind")
    logger.info { "Uninstall kind tool" }
    FileUtils.rm_rf(KIND_DIR)
  end
end
