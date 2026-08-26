require "sam"
require "./modules/release_manager"
require "./proto/**"
require "./tasks/**"
require "./tasks/utils/utils.cr"
require "./cnf_testsuite.cr"


desc "Makes sure a cnf is in the cnf directory"
task "ensure_cnf_installed" do |_, args|
  CNFManager::Task.ensure_cnf_installed!
end

desc "Print the CNF Test Suite version"
task "version" do |_, args|
  Log.info { "VERSION: #{ReleaseManager::VERSION}" }
  puts "CNF TestSuite version: #{ReleaseManager::VERSION}".colorize(:green)
end

desc "Maintainers: create or update the GitHub release for the current version"
task "upsert_release" do |_, args|
  Log.info { "upserting release on: #{ReleaseManager::VERSION}" }

  ghrm = ReleaseManager::GithubReleaseManager.new("lfn-cnti/testsuite")

  release, asset = ghrm.upsert_release(version=ReleaseManager::VERSION)
  if release
    puts "Created a release for: #{ReleaseManager::VERSION}".colorize(:green)
  else
    puts "Not creating a release for: #{ReleaseManager::VERSION}".colorize(:red)
  end
end

desc "Emit one log line at every level; useful for checking log configuration"
task "test" do
  Log.debug { "debug test" }
  Log.info { "info test" }
  Log.warn { "warn test" }
  Log.error { "error test" }
  puts "ping"
end

desc "Print a shell completion script; `completion bash` (default) or `completion zsh`, see USAGE.md"
task "completion" do |_, args|
  shell = args.raw.first?.try(&.to_s) || CLICompletion::DEFAULT_SHELL
  unless CLICompletion::SHELLS.includes?(shell)
    stdout_failure "Unknown shell '#{shell}'. Usage: #{CLIHelp::BIN_NAME} completion [#{CLICompletion::SHELLS.join("|")}]"
    exit USAGE_EXIT_CODE
  end
  puts CLICompletion.script(shell)
end

begin
  # -h/--version are recorded by the OptionParser in logging.cr at require time;
  # act on them here, where every task is registered and help can list them all.
  if CLIInvocation.version_requested?
    puts "CNF TestSuite version: #{ReleaseManager::VERSION}"
    exit 0
  end

  # A bare invocation shows help, as does -h.
  if CLIInvocation.help_requested? || ARGV.empty?
    puts CLIHelp.main_page
    exit 0
  end

  # Every task on the line runs in order with the parsed arguments; SAM only
  # ever sees a task path and a ready-made Sam::Args.
  invocation = CLIParser.parse!(ARGV)
  invocation.tasks.each { |task| Sam.invoke(task, invocation.args) }

  if CNFManager::Points::Results.file_exists?
    # One stable line per run for scripts to grep; the pointer is the path
    # that does not change between runs.
    stdout_info "Results: #{CNFManager::Points::Results.file} (latest: #{CNFManager::Points::Results.latest})"
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    case (yaml["exit_code"])
    when 1
      exit 1
    when 2
      exit 2
    end
  end
rescue e : CLIParser::UsageError
  e.errors.each { |error| stdout_failure error }
  exit USAGE_EXIT_CODE
rescue e : Sam::NotFound
  stdout_failure e.message.to_s
  if suggestion = CLIHelp.suggestion_for(e.task_path)
    stdout_failure "Did you mean '#{suggestion}'?"
  end
  stdout_info "Run `#{CLIHelp::BIN_NAME} help tasks` to list every task."
  exit USAGE_EXIT_CODE
rescue e : Helm::Binary::HelmBinaryNotFoundError
  # Not a crash: every helm shell-out funnels through Binary.get, which makes
  # this the one choke point for "helm is not installed" (#2457). A missing
  # prerequisite gets guidance and exit 1, not a backtrace and exit 2.
  stdout_failure e.message.to_s
  stdout_failure "Run `#{CLIHelp::BIN_NAME} setup` to install the prerequisites."
  exit 1
rescue e
  # An exception nothing caught: the suite itself broke, the same verdict as
  # a test that errored.
  puts e.backtrace.join("\n"), e
  exit CNFManager::Task::CRITICAL_FAILURE_CODE
end
