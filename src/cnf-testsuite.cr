require "sam"
require "./modules/release_manager"
require "./proto/**"
require "./tasks/**"
require "./tasks/utils/utils.cr"
require "./cnf_testsuite.cr"


desc "The CNF Test Suite program enables interoperability of CNFs from multiple vendors running on top of Kubernetes supplied by different vendors. The goal is to provide an open source test suite to enable both open and closed source CNFs to demonstrate conformance and implementation of best practices."
task "all", ["workload", "platform"] do  |_, args|
  Log.debug { "all" }

  total = CNFManager::Points.total_points
  max_points = CNFManager::Points.total_max_points

  if total > 0
    stdout_success "Final score: #{total} of #{max_points}"
  else
    stdout_failure "Final score: #{total} of #{max_points}"
  end

  update_yml("#{CNFManager::Points::Results.file}", "points", total)
  update_yml("#{CNFManager::Points::Results.file}", "maximum_points", max_points)

  if CNFManager::Points.failed_required_tasks.size > 0
    stdout_failure "Test Suite failed!"
    stdout_failure "Failed required tasks: #{CNFManager::Points.failed_required_tasks.inspect}"
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end

    Log.debug { "results yaml: #{yaml}" }
    if (yaml["exit_code"]) != 2
      update_yml("#{CNFManager::Points::Results.file}", "exit_code", "1")
    end
  end
  stdout_info "Test results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
end

desc "The CNF Test Suite program enables interoperability of CNFs from multiple vendors running on top of Kubernetes supplied by different vendors. The goal is to provide an open source test suite to enable both open and closed source CNFs to demonstrate conformance and implementation of best practices."
task "workload", ["ensure_cnf_installed", "setup:configuration_file_setup", "compatibility","state", "security", "configuration", "observability", "microservice", "resilience"] do  |_, args|
  Log.debug { "workload" }

  total = CNFManager::Points.total_points("workload")
  max_points = CNFManager::Points.total_max_points("workload")
  if total > 0
    stdout_success "Final workload score: #{total} of #{max_points}"
  else
    stdout_failure "Final workload score: #{total} of #{max_points}"
  end

  update_yml("#{CNFManager::Points::Results.file}", "points", total)
  update_yml("#{CNFManager::Points::Results.file}", "maximum_points", max_points)

  if CNFManager::Points.failed_required_tasks.size > 0
    stdout_failure "Test Suite failed!"
    stdout_failure "Failed required tasks: #{CNFManager::Points.failed_required_tasks.inspect}"
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    Log.info { "results yaml: #{yaml}" }
    if (yaml["exit_code"]) != 2
      update_yml("#{CNFManager::Points::Results.file}", "exit_code", "1")
    end
  end
  stdout_info "Test results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
end

desc "Makes sure a cnf is in the cnf directory"
task "ensure_cnf_installed" do |_, args|
  CNFManager::Task.ensure_cnf_installed!
end

task "version" do |_, args|
  Log.info { "VERSION: #{ReleaseManager::VERSION}" }
  puts "CNF TestSuite version: #{ReleaseManager::VERSION}".colorize(:green)
end

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
complete -W "#{Sam.root_namespace.all_tasks.map(&.name).join(" ")}" #{bin_name}
TEMPLATE

puts completion_template
end

# Sam.help
begin
  puts `#{PROGRAM_NAME} help` if ARGV.empty?
  # See issue #426 for exit code requirement
  Sam.process_tasks(ARGV.clone)

  if CNFManager::Points::Results.file_exists?
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    Log.info { "results yaml: #{yaml}" }
    case (yaml["exit_code"])
    when 1
      exit 1
    when 2
      exit 2
    end
  end
rescue e : Sam::NotFound
  puts e.message
  exit 1
rescue e
  puts e.backtrace.join("\n"), e
  exit 1
end
