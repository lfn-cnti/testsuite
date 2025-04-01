require "sam"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up api snoop"
  task "install_apisnoop" do |_, args|
    logger = SLOG.for("install_apisnoop")
    logger.info { "Installing APISnoop tool" }

    ApiSnoop.new.install
  end
end
