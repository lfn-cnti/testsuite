# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../../modules/docker_client"
require "halite"
require "totem"
require "./cert_utils.cr"

desc "The CNF test suite checks to see if CNFs follows microservice principles"
task "cert_microservice" do |t, args|
  puts "Microservice Tests".colorize(Colorize::ColorRGB.new(0, 255, 255))

  exclude = get_excluded_tasks(args)
  essential_only = args.raw.includes? "essential"
  tags = ["microservice", "cert"]
  tags << "essential" if essential_only

  invoke_tasks_by_tag_list(t, tags, exclude_tasks: exclude)

  cert_stdout_score(tags, "microservice", exclude_warning: !exclude.empty?)
  case "#{ARGV.join(" ")}" 
  when /cert_microservice/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end
