require "sam"
require "./cli_options"
require "./cli_parser"

# Exit code for CLI usage errors (sysexits EX_USAGE).
USAGE_EXIT_CODE = 64

# Report a usage error and exit with USAGE_EXIT_CODE. For mistakes that are
# visible from the command line alone -- a missing or unknown argument, a
# malformed value, a path that names no file -- before anything has run.
def usage_error!(message : String) : NoReturn
  stdout_failure message
  exit USAGE_EXIT_CODE
end

# The legacy spellings, derived from the option registry: help, completion
# and validation all read CLIOptions, so these can no longer drift from it.
KNOWN_CLI_NAMED_ARGS = CLIOptions::ALL.select(&.takes_value?).compact_map(&.legacy)
NUMERIC_CLI_NAMED_ARGS = CLIOptions::ALL.select(&.numeric).compact_map(&.legacy)
KNOWN_CLI_FLAGS = CLIOptions.flags.compact_map(&.legacy)

# True when `name` was one of the tasks invoked on the command line, as parsed
# by CLIParser. Replaces the old unanchored `case ARGV.join(" ") when /name/`
# checks, where e.g. /ran/ matched any invocation containing "ran"
# (rolling_version_change, a fixture path, ...).
def invoked_task?(name : String) : Bool
  CLIInvocation.tasks.includes?(name)
end
