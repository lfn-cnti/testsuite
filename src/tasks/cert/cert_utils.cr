require "../utils/utils.cr"

def get_excluded_tasks(args)
  if args.named.has_key? "exclude"
    exclude = args.named["exclude"]
    if exclude.is_a? String
      exclude = exclude.includes?(",") ? exclude.split(",") : exclude.split(" ")
    else
      usage_error! "Exclude argument should contain string value Ex.: (exclude=\"increase_decrease_capacity single_process_type\")"
    end
  else
    exclude = [] of String
  end
  unless exclude.empty?
    cert_tests = CNFManager::Points.tasks_by_tag_intersection(["cert"])
    exclude.each do |task|
      unless cert_tests.includes? task
        usage_error! "Excluded task \"#{task}\" is not a cert test, check syntax"
      end
    end
  end
  exclude
end

  
def invoke_tasks_by_tag_list(parent_task, args, tags, exclude_tasks=[] of String)
  tasks = CNFManager::Points.tasks_by_tag_intersection(tags)
  tasks.each do |task|
    unless exclude_tasks.includes? task
      parent_task.invoke(task, args)
    end
  end
end

# One cert category: the colored section heading, the tag-selected member
# tests (honoring `exclude=` and the `essential` flag), and the section score.
# The results-file path is printed once per run by the entrypoint.
def run_cert_category(t, args, category : String, heading : String, score_name : String? = nil)
  puts heading.colorize(Colorize::ColorRGB.new(0, 255, 255))

  exclude = get_excluded_tasks(args)
  tags = [category, "cert"]
  tags << "essential" if args.raw.includes?("essential")

  invoke_tasks_by_tag_list(t, args, tags, exclude_tasks: exclude)
  cert_stdout_score(tags, score_name || category, exclude_warning: !exclude.empty?)
end

def cert_stdout_score(tags, full_name, exclude_warning = false)
  stdout_score(tags, full_name)
  if exclude_warning
    stdout_info "With \"exclude\" parameter, number of total tests executed isn't correct, keep in mind.".colorize(:yellow)
  end
end
