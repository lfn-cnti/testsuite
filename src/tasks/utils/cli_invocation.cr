# Flags recognized by the top-level OptionParser in logging.cr. That parser runs
# at require time, before every task is registered, so it only records what was
# asked for - the entry point acts on it once the task tree is complete and can
# therefore render a help page that lists everything.
class CLIInvocation
  class_property? help_requested : Bool = false
  class_property? version_requested : Bool = false
end
