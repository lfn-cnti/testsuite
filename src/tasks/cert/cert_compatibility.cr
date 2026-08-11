# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "The CNF test suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s kubectl"
task "cert_compatibility" do |t, args|
  puts "Compatibility, Installability & Upgradability Tests".colorize(Colorize::ColorRGB.new(0, 255, 255))

  exclude = get_excluded_tasks(args)
  essential_only = args.raw.includes? "essential"
  tags = ["compatibility", "cert"]
  tags << "essential" if essential_only

  invoke_tasks_by_tag_list(t, args, tags, exclude_tasks: exclude)
  
  cert_stdout_score(tags, "Compatibility, Installability, and Upgradeability", exclude_warning: !exclude.empty?)

  case "#{ARGV.join(" ")}" 
  when /cert_compatibility/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end

end

task "cert_compatibility_title" do |_, args|
  
end
