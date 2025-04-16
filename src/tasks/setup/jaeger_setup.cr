require "sam"
require "file_utils"
require "colorize"
require "totem"

namespace "setup" do
  desc "Install Jaeger"
  task "install_jaeger" do |_, args|
    SLOG.for("install_jaeger").info { "Installing Jaeger tool" }
    JaegerManager.install
  end

  desc "Uninstall Jaeger"
  task "uninstall_jaeger" do |_, args|
    SLOG.for("uninstall_jaeger").info { "Uninstalling Jaeger tool" }
    JaegerManager.uninstall
  end
end
