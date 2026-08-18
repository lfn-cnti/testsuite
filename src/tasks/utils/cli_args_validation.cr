require "sam"

# Exit code for CLI usage errors (sysexits EX_USAGE).
USAGE_EXIT_CODE = 64

# Every key=value argument some task actually reads.
KNOWN_CLI_NAMED_ARGS = [
  "cnf-config", "cnf-path", "timeout", "input_config", "output_config",
  "exclude", "pod_labels", "baseline_count",
]
# Named arguments whose value must be an integer.
NUMERIC_CLI_NAMED_ARGS = ["timeout", "baseline_count"]
# Every bare-word flag some task actually reads from the raw arguments.
KNOWN_CLI_FLAGS = [
  "strict", "essential", "poc", "wip", "alpha", "beta", "destructive",
  "skip_wait_for_install", "skip_wait_for_uninstall",
]

# Validates raw CLI tokens before SAM processes them. Previously every typo was
# silently ignored: unknown key=value args and flags did nothing, exclusions
# matching no task were dropped, and a second task name on the command line was
# swallowed as an argument. Unknown input is now a usage error; the two
# warn-only cases stay warnings for compatibility.
def validate_cli_args!(argv : Array(String))
  task_paths = Sam.root_namespace.all_tasks.map(&.path)
  errors = [] of String
  expect_task = true

  argv.each do |token|
    if token == Sam::TASK_SEPARATOR
      expect_task = true
      next
    end
    if expect_task
      # Task names themselves are validated by SAM (Sam::NotFound).
      expect_task = false
      next
    end

    if token.empty?
      errors << "Empty argument given."
    elsif token.starts_with?("~")
      unless task_paths.includes?(token[1..])
        stdout_warning "Exclusion '#{token}' does not match any task and will be ignored."
      end
    elsif token.includes?("=")
      key, value = token.split("=", 2)
      if !KNOWN_CLI_NAMED_ARGS.includes?(key)
        errors << "Unknown argument '#{key}='. Known arguments: #{KNOWN_CLI_NAMED_ARGS.join(", ")}."
      elsif NUMERIC_CLI_NAMED_ARGS.includes?(key) && value.to_i?.nil?
        errors << "Invalid value for '#{key}=': '#{value}' is not a number."
      end
    elsif token.starts_with?("-")
      errors << "Unknown option '#{token}'. Supported options: -l/--loglevel LEVEL, -h/--help."
    elsif KNOWN_CLI_FLAGS.includes?(token)
      # valid bare flag
    elsif task_paths.includes?(token)
      stdout_warning "'#{token}' is a task name in an argument position and will be ignored. To run multiple tasks, separate them with '#{Sam::TASK_SEPARATOR}': cnf-testsuite <task1> #{Sam::TASK_SEPARATOR} <task2>"
    else
      errors << "Unknown flag '#{token}'. Known flags: #{KNOWN_CLI_FLAGS.join(", ")}."
    end
  end

  unless errors.empty?
    errors.each { |error| stdout_failure error }
    exit USAGE_EXIT_CODE
  end
end

# True when `name` was one of the tasks invoked on the command line: the first
# token, or any token following the '@' task separator. Replaces the old
# unanchored `case ARGV.join(" ") when /name/` checks, where e.g. /ran/ matched
# any invocation containing "ran" (rolling_version_change, a fixture path, ...).
def invoked_task?(name : String) : Bool
  expect_task = true
  ARGV.each do |token|
    if token == Sam::TASK_SEPARATOR
      expect_task = true
      next
    end
    if expect_task
      return true if token == name
      expect_task = false
    end
  end
  false
end
