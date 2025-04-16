require "sam"
require "file_utils"
require "colorize"
require "totem"

desc "Install FluentD"
task "install_fluentd" do |_, args|
  FluentManager::FluentD.new.install
end

desc "Uninstall FluentD"
task "uninstall_fluentd" do |_, args|
  FluentManager::FluentD.new.uninstall
end

desc "Install FluentDBitnami"
task "install_fluentdbitnami" do |_, args|
  FluentManager::FluentDBitnami.new.install
end

desc "Uninstall FluentDBitnami"
task "uninstall_fluentdbitnami" do |_, args|
  FluentManager::FluentDBitnami.new.uninstall
end

desc "Install FluentBit"
task "install_fluentbit" do |_, args|
  FluentManager::FluentBit.new.install
end

desc "Uninstall FluentBit"
task "uninstall_fluentbit" do |_, args|
  FluentManager::FluentBit.new.uninstall
end
