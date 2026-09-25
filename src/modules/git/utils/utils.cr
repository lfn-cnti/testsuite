require "totem"
require "colorize"
require "log"
require "file_utils"
require "../constants.cr"

# These mirror the top-level helpers in tasks/utils/utils.cr and honor the same
# `--output json` gate, so the git setup checks never write to stdout in JSON
# mode (stdout is reserved for the single results document).
def stdout_info(msg)
  (json_output? ? STDERR : STDOUT).puts msg
end

def stdout_success(msg)
  json_output? ? STDERR.puts(msg) : STDOUT.puts(msg.colorize(:green))
end

def stdout_warning(msg)
  json_output? ? STDERR.puts(msg) : STDOUT.puts(msg.colorize(:yellow))
end

def stdout_failure(msg)
  json_output? ? STDERR.puts(msg) : STDOUT.puts(msg.colorize(:red))
end

def local_git_path
  File.join(FileUtils.pwd, GitClient::DEFAULT_LOCAL_BINARY_PATH)
end
