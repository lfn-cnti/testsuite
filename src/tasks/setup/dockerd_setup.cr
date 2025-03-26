require "sam"
require "file_utils"
require "colorize"
require "totem"
require "./utils/utils.cr"

desc "The dockerd tool is used to run docker commands against the cluster."
task "install_dockerd" do |_, args|
  Log.debug { "install_dockerd" }
  install_status = Dockerd.install
  unless install_status
    Log.error { "Dockerd_Install failed.".colorize(:red) }
  end
  Log.info { "Dockerd_Install status: #{install_status}" }
end

desc "Uninstall dockerd"
task "uninstall_dockerd" do |_, args|
  Dockerd.uninstall
end
