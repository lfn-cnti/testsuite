require "sam"
require "./cli_options"
require "./cli_parser"
require "./cli_invocation"

# Exit code for CLI usage errors (sysexits EX_USAGE).
USAGE_EXIT_CODE = 64

# Report a usage error and exit with USAGE_EXIT_CODE. For mistakes that are
# visible from the command line alone -- a missing or unknown argument, a
# malformed value, a path that names no file -- before anything has run.
# The single sink for every command-line usage message (the ones that exit 64):
# an unknown/malformed option, an unknown task, an unknown completion shell.
# All go to stderr, in text and JSON mode alike, so they are never split across
# streams and stdout stays clean (an empty document in JSON mode).
# (Colorize.enabled is decided by STDOUT.tty?, so with stdout on a terminal and
# stderr redirected the colour codes land in the file — a minor, documented
# caveat, the same one noted for the JSON-mode stderr trail.)
def stderr_usage(message : String) : Nil
  STDERR.puts message.colorize(:red)
end

def usage_error!(message : String) : NoReturn
  stderr_usage message
  exit USAGE_EXIT_CODE
end

# True when `name` was one of the tasks invoked on the command line, as parsed
# by CLIParser. Replaces the old unanchored `case ARGV.join(" ") when /name/`
# checks, where e.g. /ran/ matched any invocation containing "ran"
# (rolling_version_change, a fixture path, ...).
def invoked_task?(name : String) : Bool
  CLIInvocation.tasks.includes?(name)
end
