# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "The CNF test suite checks to see if the CNFs are resilient to failures."
 task "cert_resilience" do |t, args|
  puts "Reliability, Resilience, and Availability Tests".colorize(Colorize::ColorRGB.new(0, 255, 255))

  exclude = get_excluded_tasks(args)
  essential_only = args.raw.includes? "essential"
  tags = ["resilience", "cert"]
  tags << "essential" if essential_only

  invoke_tasks_by_tag_list(t, args, tags, exclude_tasks: exclude)

  Log.debug { "resilience" }
  Log.trace { "resilience args.raw: #{args.raw}" }
  Log.trace { "resilience args.named: #{args.named}" }
  cert_stdout_score(tags, "Reliability, Resilience, and Availability", exclude_warning: !exclude.empty?)
  if invoked_task?("cert_resilience")
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end
