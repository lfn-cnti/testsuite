# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "In order to maintain, debug, and have insight into a protected environment, its infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends itself to metrics, tracing, and logging."
task "cert_observability" do |t, args|
  puts "Observability and Diagnostics Tests".colorize(Colorize::ColorRGB.new(0, 255, 255))

  exclude = get_excluded_tasks(args)
  essential_only = args.raw.includes? "essential"
  tags = ["observability", "cert"]
  tags << "essential" if essential_only

  invoke_tasks_by_tag_list(t, args, tags, exclude_tasks: exclude)

  cert_stdout_score(tags, "Observability and Diagnostics", exclude_warning: !exclude.empty?)
  if invoked_task?("cert_observability")
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end
