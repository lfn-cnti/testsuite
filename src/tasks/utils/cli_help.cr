require "sam"
require "levenshtein"

# SAM keeps a task's dependency list private, and its NotFound exception drops
# the path it could not resolve. Help groups tasks by the very aggregates the
# suite runs, so the listing can never drift from what the tasks actually do,
# and an unknown task can be matched against the real ones. Reopening is the
# pattern already used for Sam::Args in sam_args_patch.cr.
class Sam::Task
  def dependency_names : Array(String)
    @deps
  end
end

class Sam::NotFound < Exception
  getter task_path : String = ""

  def initialize(task)
    @task_path = task.to_s
    @message = "Task #{task} was not found"
  end
end

# Renders the CLI help. SAM's own help is a flat ShellTable dump of every
# registered task that also shells out to `tput cols`, which crashes when TERM
# is unset (containers, CI). This replaces it with a curated page plus a grouped
# listing, and uses a fixed width so there is nothing to shell out to.
module CLIHelp
  BIN_NAME = "cnf-testsuite"

  WIDTH       = 96
  NAME_COLUMN = 34

  # Namespaces that exist only to serve the task framework itself.
  HIDDEN_NAMESPACES = ["generate"]

  # Workload test categories, in the order `workload` runs them.
  WORKLOAD_CATEGORIES = [
    "compatibility", "state", "security", "configuration",
    "observability", "microservice", "resilience",
  ]

  # A task whose final path segment starts with '_' is internal and never
  # listed. A convention beats a hide-list that silently rots as tasks are added.
  def self.hidden?(task : Sam::Task) : Bool
    return true if task.name.starts_with?("_")
    HIDDEN_NAMESPACES.any? { |namespace| task.path.starts_with?("#{namespace}:") }
  end

  def self.all_tasks : Array(Sam::Task)
    Sam.root_namespace.all_tasks
  end

  def self.visible_tasks : Array(Sam::Task)
    all_tasks.reject { |task| hidden?(task) }
  end

  def self.find_task(path : String) : Sam::Task?
    all_tasks.find { |task| task.path == path }
  end

  # Resolves a dependency the way SAM does: a task inside a namespace names its
  # siblings without the namespace prefix, so "cluster_admin" written inside
  # `platform:security` means `platform:cluster_admin`.
  def self.find_task_near(context : Sam::Task, name : String) : Sam::Task?
    prefix = context.path.rpartition(":")[0]
    return find_task(name) if prefix.empty?
    find_task("#{prefix}:#{name}") || find_task(name)
  end

  # Closest visible task name to `name`, when one is near enough to be worth
  # suggesting.
  def self.suggestion_for(name : String) : String?
    paths = visible_tasks.map(&.path)
    # A namespaced task is far from its own bare name by edit distance - the
    # prefix alone is nine characters - so match the last segment first. That is
    # what someone typing `k8s_conformance` for `platform:k8s_conformance` needs.
    exact_segment = paths.find { |path| path.rpartition(":")[2] == name && path != name }
    exact_segment || Levenshtein.find(name, paths, 3)
  end

  # Ordered groups of {title, tasks}. The test groups expand the suite's own
  # aggregates rather than repeating their contents here. Whatever no group
  # claims is listed under "Other", so a newly added task can never go missing.
  def self.groups : Array(Tuple(String, Array(Sam::Task)))
    claimed = Set(String).new
    result = [] of Tuple(String, Array(Sam::Task))

    add = ->(title : String, paths : Array(String)) do
      tasks = [] of Sam::Task
      paths.each do |path|
        task = find_task(path)
        next if task.nil? || hidden?(task) || claimed.includes?(task.path)
        claimed << task.path
        tasks << task
      end
      result << {title, tasks} unless tasks.empty?
      nil
    end

    add.call("Getting started", [
      "setup", "cnf_install", "cnf_uninstall", "validate_config",
      "cnf_setup", "cnf_cleanup", "uninstall_all", "tools_uninstall",
    ])
    add.call("Test suites", ["all", "workload", "platform", "cert", "static"])

    WORKLOAD_CATEGORIES.each do |category|
      task = find_task(category)
      next if task.nil?
      add.call("Workload tests: #{category}", [category] + task.dependency_names)
    end

    platform_paths = [] of String
    if platform = find_task("platform")
      # `platform` also depends on a setup task; that belongs under setup.
      platform_paths.concat(platform.dependency_names.reject(&.starts_with?("setup:")))
    end
    platform_paths.concat(visible_tasks.map(&.path).select(&.starts_with?("platform:")).sort)
    add.call("Platform tests", platform_paths)

    # 5G and RAN suites are aggregates in their own right rather than members of
    # a workload category.
    telco_paths = [] of String
    ["5g", "ran"].each do |suite|
      task = find_task(suite)
      next if task.nil?
      telco_paths << suite
      telco_paths.concat(task.dependency_names)
    end
    telco_paths.concat(visible_tasks.map(&.path).select { |path|
      path.starts_with?("smf_upf") || path.starts_with?("suci") || path.starts_with?("oran")
    }.sort)
    add.call("5G and RAN tests", telco_paths)

    add.call("Certification", visible_tasks.map(&.path).select(&.starts_with?("cert")).sort)

    # Tools the suite can install into the cluster on demand, outside the
    # `setup:` namespace.
    add.call("Tool management", visible_tasks.map(&.path).select { |path|
      path.starts_with?("install_") || path.starts_with?("uninstall_")
    }.sort)
    add.call("Setup helpers", visible_tasks.map(&.path).select(&.starts_with?("setup:")).sort)
    add.call("Utilities", [
      "help", "completion", "version", "update_config", "delete_results",
      "test", "upsert_release",
    ])

    rest = visible_tasks.reject { |task| claimed.includes?(task.path) }.sort_by(&.path)
    result << {"Other", rest} unless rest.empty?
    result
  end

  def self.main_page : String
    named_args = KNOWN_CLI_NAMED_ARGS.join(", ")
    flags = KNOWN_CLI_FLAGS.join(", ")

    <<-HELP
    The CNTi Test Suite validates a Cloud Native Function against cloud native
    best practices by running tests against a live Kubernetes cluster.

    USAGE
      #{BIN_NAME} [options] <task> [arguments] [~exclusions] [#{Sam::TASK_SEPARATOR} <task> ...]

    TYPICAL WORKFLOW
      #{BIN_NAME} setup                                    install prerequisites (once)
      #{BIN_NAME} cnf_install cnf-config=./cnf-testsuite.yml
      #{BIN_NAME} cert                                     run the certification tests
      #{BIN_NAME} cnf_uninstall

    TEST SUITES
      all         workload and platform tests
      workload    tests against the installed CNF
      platform    tests against the Kubernetes platform itself
      cert        certification run; exits 0 when the CNF is certified

    OPTIONS
      -l, --loglevel LEVEL   trace, debug, info, notice, warn, error, fatal (default: error)
      -h, --help             show this help and exit
          --version          print the version and exit

    ARGUMENTS (key=value, after the task name)
      cnf-config=PATH   a cnf-testsuite.yml or the directory holding one (alias: cnf-path)
      timeout=SECONDS   how long to wait for install and uninstall operations
      results-dir=PATH  where results files go (default: ./results, or $CNF_TESTSUITE_RESULTS_DIR)
      All known arguments: #{named_args}

    FLAGS
      #{flags}

    EXCLUSIONS AND MULTIPLE TASKS
      ~<task>   skip a task within a suite, e.g. `#{BIN_NAME} all ~resilience`
      #{Sam::TASK_SEPARATOR}         run several tasks in one invocation, e.g. `#{BIN_NAME} liveness #{Sam::TASK_SEPARATOR} readiness`

    EXIT CODES
      0   the run met its objective          2   a test errored (the suite broke)
      1   it did not                         64  usage error, before any test ran

    MORE
      #{BIN_NAME} help tasks     list every task, grouped by category
      #{BIN_NAME} help <task>    show what a single task does
      Documentation: https://github.com/lfn-cnti/testsuite/blob/main/USAGE.md
    HELP
  end

  def self.task_list : String
    String.build do |io|
      io << "Tasks. Run `" << BIN_NAME << " help <task>` for detail on one of them.\n"
      groups.each do |title, tasks|
        io << "\n" << title.upcase << "\n"
        tasks.each { |task| io << row(task.path, task.description) }
      end
    end
  end

  def self.task_detail(path : String) : String?
    task = find_task(path)
    return nil if task.nil? || hidden?(task)

    String.build do |io|
      io << BIN_NAME << " " << task.path << "\n\n"
      description = task.description
      if description.empty?
        io << "  (no description)\n"
      else
        wrap(description, WIDTH - 2).each { |line| io << "  " << line << "\n" }
      end

      deps = task.dependency_names.compact_map { |name| find_task_near(task, name) }.reject { |t| hidden?(t) }
      parents = visible_tasks.select do |candidate|
        candidate.path != task.path && candidate.dependency_names.includes?(task.path)
      end
      io << "\n" unless deps.empty? && parents.empty?
      io << labelled_list("Runs first", deps.map(&.path)) unless deps.empty?
      io << labelled_list("Part of", parents.map(&.path).sort) unless parents.empty?
    end
  end

  # Fixed-width word wrap. Deliberately not terminal-aware: querying the
  # terminal is what made SAM's help crash when TERM was unset.
  private def self.wrap(text : String, width : Int32) : Array(String)
    words = text.split(/\s+/).reject(&.empty?)
    return [""] of String if words.empty?

    lines = [] of String
    current = ""
    words.each do |word|
      if current.empty?
        current = word
      elsif current.size + 1 + word.size <= width
        current = "#{current} #{word}"
      else
        lines << current
        current = word
      end
    end
    lines << current unless current.empty?
    lines
  end

  private def self.labelled_list(label : String, values : Array(String)) : String
    prefix = "  #{label}: "
    lines = wrap(values.join(", "), WIDTH - prefix.size)
    String.build do |io|
      io << prefix << lines.first << "\n"
      lines[1..].each { |line| io << " " * prefix.size << line << "\n" }
    end
  end

  private def self.row(name : String, description : String) : String
    label = "  #{name}"
    lines = wrap(description, WIDTH - NAME_COLUMN)
    String.build do |io|
      if label.size >= NAME_COLUMN
        io << label << "\n"
        lines.each { |line| io << " " * NAME_COLUMN << line << "\n" unless line.empty? }
      else
        io << label.ljust(NAME_COLUMN) << lines.first << "\n"
        lines[1..].each { |line| io << " " * NAME_COLUMN << line << "\n" }
      end
    end
  end
end

desc "Show usage; `help tasks` lists every task, `help <task>` describes one"
task "help" do |_, args|
  topic = args.raw.first?.try(&.to_s)

  case topic
  when nil
    puts CLIHelp.main_page
  when "tasks"
    puts CLIHelp.task_list
  else
    detail = CLIHelp.task_detail(topic)
    if detail
      puts detail
    else
      stdout_failure "Unknown task '#{topic}'."
      if suggestion = CLIHelp.suggestion_for(topic)
        stdout_failure "Did you mean '#{suggestion}'?"
      end
      stdout_info "Run `#{CLIHelp::BIN_NAME} help tasks` to list every task."
      exit USAGE_EXIT_CODE
    end
  end
end
