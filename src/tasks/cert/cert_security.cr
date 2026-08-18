# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "CNF containers should be isolated from one another and the host.  The CNF Test suite uses tools like Sysdig Inspect and gVisor"
task "cert_security" do |t, args|
  puts "Security Tests".colorize(Colorize::ColorRGB.new(0, 255, 255))

  exclude = get_excluded_tasks(args)
  essential_only = args.raw.includes? "essential"
  tags = ["security", "cert"]
  tags << "essential" if essential_only

  invoke_tasks_by_tag_list(t, args, tags, exclude_tasks: exclude)

  cert_stdout_score(tags, "security", exclude_warning: !exclude.empty?)
  if invoked_task?("cert_security")
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end
