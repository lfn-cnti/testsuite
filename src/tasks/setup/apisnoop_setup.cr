require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "Sets up api snoop"
task "install_apisnoop" do |_, args|
  Log.debug { "install_apisnoop" }
  ApiSnoop.new().install()
end
