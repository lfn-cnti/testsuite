require "../utils/utils.cr"

# Every task carrying all of `tags`, invoked with the caller's arguments. A
# task named by --skip is left out by SAM itself, which checks the arguments
# for its `~path` before running it.
def invoke_tasks_by_tag_list(parent_task, args, tags)
  CNFManager::Points.tasks_by_tag_intersection(tags).each do |task|
    parent_task.invoke(task, args)
  end
end

# One cert category: the colored section heading, the tag-selected member
# tests (honoring --skip and --essential), and the section score. The
# results-file path is printed once per run by the entrypoint.
def run_cert_category(t, args, category : String, heading : String, score_name : String? = nil)
  puts heading.colorize(Colorize::ColorRGB.new(0, 255, 255))

  tags = [category, "cert"]
  tags << "essential" if args.raw.includes?("essential")

  invoke_tasks_by_tag_list(t, args, tags)
  stdout_score(tags, score_name || category)
end
