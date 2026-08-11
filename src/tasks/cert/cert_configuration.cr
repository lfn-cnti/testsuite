# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "json"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "Configuration should be managed in a declarative manner, using ConfigMaps, Operators, or other declarative interfaces."

task "cert_configuration" do |t, args|
  puts "Configuration Tests".colorize(Colorize::ColorRGB.new(0, 255, 255))

  exclude = get_excluded_tasks(args)
  essential_only = args.raw.includes? "essential"
  tags = ["configuration", "cert"]
  tags << "essential" if essential_only

  invoke_tasks_by_tag_list(t, args, tags, exclude_tasks: exclude)

  cert_stdout_score(tags, "configuration", exclude_warning: !exclude.empty?)
  case "#{ARGV.join(" ")}" 
  when /cert_configuration/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end
