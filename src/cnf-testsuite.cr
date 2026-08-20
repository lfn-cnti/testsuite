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

# https://www.thegeekstuff.com/2013/12/bash-completion-complete/
# https://kubernetes.io/docs/tasks/tools/install-kubectl/#enable-kubectl-autocompletion
# https://stackoverflow.com/questions/43794270/disable-or-unset-specific-bash-completion
desc "Install Shell Completion: check https://github.com/lfn-cnti/testsuite/blob/main/USAGE.md for usage"
task "completion" do |_|

# assumes bash completion feel free to make a pr for zsh and check an arg for it
bin_name = "cnf-testsuite"

completion_template = <<-TEMPLATE
# to remove
# complete -r #{bin_name}
complete -W "#{CLIHelp.visible_tasks.map(&.path).join(" ")}" #{bin_name}
TEMPLATE

puts completion_template
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

  argv = TaskAliases.resolve_exclusions(ARGV.clone)
  validate_cli_args!(argv)
  # See issue #426 for exit code requirement
  Sam.process_tasks(argv)

  if CNFManager::Points::Results.file_exists?
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
rescue e : Sam::NotFound
  stdout_failure e.message.to_s
  if suggestion = CLIHelp.suggestion_for(e.task_path)
    stdout_failure "Did you mean '#{suggestion}'?"
  end
  stdout_info "Run `#{CLIHelp::BIN_NAME} help tasks` to list every task."
  exit 1
rescue e
  puts e.backtrace.join("\n"), e
  exit 1
end
