# What the command line asked for, as parsed once at the entry point. -h and
# --version are recorded earlier still, by the OptionParser in logging.cr that
# runs at require time before any task exists.
class CLIInvocation
  class_property? help_requested : Bool = false
  class_property? version_requested : Bool = false

  @@tasks = [] of String
  @@named = {} of String => String

  # Records the parsed invocation: every task named on the line, and the
  # named option values.
  def self.record(invocation)
    @@tasks = invocation.tasks
    @@named = {} of String => String
    invocation.args.named.each { |key, value| @@named[key] = value.to_s }
  end

  # The tasks named on the command line, in order.
  def self.tasks : Array(String)
    @@tasks
  end

  # A named option's value as given on the command line, or nil.
  def self.option(name : String) : String?
    @@named[name]?
  end
end
