require "sam"
require "file_utils"
require "colorize"
require "totem"

desc "Install UERANSIM"
task "install_ueransim" do |_, args|
  Log.info {"UERANSIM Setup"}
  if args["cnf-config"]?
  cnf_config_file = args["cnf-config"].as(String)
  config = CNFInstall::Config.parse_cnf_config_from_file(cnf_config_file)
  UERANSIM.install(config)
  else
    puts "you must provide a cnf-testsuite.yml".colorize(:red)
  end
end

desc "Uninstall UERANSIM"
task "uninstall_ueransim" do |_, args|
  Log.info {"UERANSIM Uninstall"}
  UERANSIM.uninstall
end

