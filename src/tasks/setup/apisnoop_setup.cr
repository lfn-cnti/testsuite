require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

namespace "setup" do
  desc "Sets up api snoop"
  task "install_apisnoop" do |_, args|
    SLOG.for("install_apisnoop").info { "Installing APISnoop tool" }
    ApiSnoop.new.install
  end
end
