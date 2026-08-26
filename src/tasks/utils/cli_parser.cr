require "sam"
require "levenshtein"
require "./cli_options"
require "./cli_invocation"
require "./cli_help"
require "./test_metadata"

# Turns the command line into task paths and their arguments before SAM sees
# it. SAM's own argument parsing is bypassed: it only ever receives a task path
# and a ready-made Sam::Args, so its historical `-flag`-eats-the-next-token and
# `=`-truncation behaviors cannot reach a task.
#
# Grammar (GNU-style; options may appear anywhere on the line):
#   cnf-testsuite [--option VALUE|--option=VALUE|--flag]... <task> [<task>...]
#
# The retired spellings - `key=value`, bare flag words, `~task` and the `@`
# separator - are recognized only to name their replacement in the error.
module CLIParser
  class UsageError < Exception
    getter errors : Array(String)

    def initialize(@errors : Array(String))
      super(@errors.join("\n"))
    end
  end

  # Tasks that take a free-form topic rather than options.
  POSITIONAL_TASKS = ["help", "completion"]
  RETIRED_SEPARATOR = "@"

  record Invocation, tasks : Array(String), args : Sam::Args

  # Parses argv, records the invocation for the rest of the run, and returns
  # the tasks to run in order with the arguments they all receive. Raises
  # UsageError with every problem found.
  def self.parse!(argv : Array(String)) : Invocation
    errors = [] of String
    task_paths = Sam.root_namespace.all_tasks.map(&.path)
    tasks = [] of String
    named = Sam::Args::AllowedHash.new
    raw = [] of Sam::Args::AllowedTypes

    i = 0
    while i < argv.size
      token = argv[i]
      positional = tasks.first?.try { |first| POSITIONAL_TASKS.includes?(first) } || false

      if token.empty?
        errors << "Empty argument given."
      elsif token.starts_with?("--")
        name, has_inline, inline = token[2..].partition("=")
        option = CLIOptions[name]?
        if option.nil?
          errors << "Unknown option '--#{name}'.#{option_suggestion(name)}"
          # Swallow what was probably its value, so one typo is one error.
          i += 1 if !has_inline.presence && argv[i + 1]?.try { |v| !v.starts_with?("-") && !task_paths.includes?(v) }
        elsif option.kind.flag?
          errors << "Option '#{option.long}' takes no value." unless inline.empty? && !has_inline.presence
          raw << option.internal_name
        else
          value = has_inline.presence ? inline : (argv[i + 1]? if argv[i + 1]?.try { |v| !v.starts_with?("--") })
          if value.nil?
            errors << "Option '#{option.long}' requires a value: #{option.long} #{option.value_label}."
          else
            i += 1 unless has_inline.presence
            if option.kind.multi?
              apply_skip(option, value, task_paths, raw, errors)
            else
              apply_value(option, value, named, errors)
            end
          end
        end
      elsif token.starts_with?("-")
        errors << "Unknown option '#{token}'. Supported: #{CLIOptions.long_names.join(", ")}, -l/--loglevel LEVEL, -h/--help, --version."
      elsif tasks.empty?
        # The first bare word names a task; SAM validates it.
        tasks << token
      elsif positional
        raw << token
      elsif token == RETIRED_SEPARATOR
        errors << "'#{RETIRED_SEPARATOR}' is no longer needed: list the tasks to run, e.g. `#{CLIHelp::BIN_NAME} liveness readiness`."
      elsif token.starts_with?("~")
        errors << "'#{token}' is no longer accepted: use `--skip #{token[1..]}`."
      elsif token.includes?("=")
        key, _, value = token.partition("=")
        if option = CLIOptions.retired_named(key)
          errors << "'#{key}=' is no longer accepted: use `#{option.long} #{option.value_label}`" +
                    (option.kind.multi? ? ", once per task." : ".")
        else
          errors << "Unknown argument '#{key}='. Options are written --name VALUE.#{option_suggestion(key)}"
        end
      elsif option = CLIOptions.retired_flag(token)
        errors << "'#{token}' is no longer accepted: use `#{option.long}`."
      elsif task_paths.includes?(token)
        tasks << token
      else
        errors << "Unknown argument '#{token}'.#{word_suggestion(token, task_paths)}"
      end
      i += 1
    end

    raise UsageError.new(errors) unless errors.empty?
    invocation = Invocation.new(tasks, Sam::Args.new(named, raw))
    CLIInvocation.record(invocation)
    invocation
  end

  private def self.apply_value(option, value : String, named, errors)
    if option.numeric && value.to_i?.nil?
      errors << "Invalid value for '#{option.long}': '#{value}' is not a number."
    elsif value.blank?
      errors << "Invalid value for '#{option.long}': #{option.value_label.downcase.presence || "a value"} is required."
    elsif option.name == "kubeconfig"
      if File.file?(value)
        # Honored by every kubectl/helm call from here on; the env var alone
        # keeps working when the option is absent.
        ENV["KUBECONFIG"] = value
      else
        errors << "Invalid value for '--kubeconfig': '#{value}' is not a file."
      end
    end
    named[option.internal_name] = value
  end

  # An exclusion is the `~path` SAM checks a task's arguments for before
  # running it, with a top-level alias resolved to the task it points at.
  private def self.apply_skip(option, value : String, task_paths, raw, errors)
    target = TaskAliases[value]? || value
    if task_paths.includes?(target)
      raw << "~#{target}"
    else
      errors << "Unknown task '#{value}' given to '#{option.long}'.#{word_suggestion(value, task_paths)}"
    end
  end

  private def self.option_suggestion(name : String) : String
    match = Levenshtein.find(name, CLIOptions::ALL.map(&.name), tolerance(name))
    match ? " Did you mean '--#{match}'?" : " Run `#{CLIHelp::BIN_NAME} help` for the options."
  end

  private def self.word_suggestion(word : String, task_paths : Array(String)) : String
    candidates = CLIOptions::ALL.map(&.long) + task_paths
    match = Levenshtein.find(word, candidates, tolerance(word))
    match ? " Did you mean '#{match}'?" : ""
  end

  # How far a suggestion may be from what was typed: up to three edits, but
  # never more than half the word, so a one-letter typo is not "corrected" to
  # an unrelated short name.
  private def self.tolerance(word : String) : Int32
    {3, word.size // 2}.min
  end
end
