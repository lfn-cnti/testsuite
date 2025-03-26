require "sam"
require "file_utils"
require "colorize"
require "totem"
require "./utils/utils.cr"

desc "Sets up the helm linter"
task "install_chart_testing" do |_, args|
  response = String::Builder.new
  Process.run("echo installing helm linter", shell: true) do |proc|
    while line = proc.output.gets
      response << line
      Log.debug { "#{line}" }
    end
  end
end

