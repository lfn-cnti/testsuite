require "sam"
require "file_utils"
require "colorize"
require "totem"

desc "Install Jaeger"
task "install_jaeger" do |_, args|
  JaegerManager.install
end

desc "Uninstall Jaeger"
task "uninstall_jaeger" do |_, args|
  JaegerManager.uninstall
end

