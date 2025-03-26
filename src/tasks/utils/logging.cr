private class CLILogLevel
  class_property level : String = ""
end

begin
  OptionParser.parse do |parser|
    parser.banner = "Usage: cnf-testsuite [arguments]"
    parser.on("-l LEVEL", "--loglevel=LEVEL", "Specifies the logging level for cnf-testsuite suite") do |level|
      CLILogLevel.level = level
    end
    parser.on("-h", "--help", "Show this help") { puts parser }
  end
rescue ex : OptionParser::InvalidOption
  puts ex
end

# First Log.setup is necessary to make sure loglevel
# method will report errors during execution.
Log.setup(Log::Severity::Error, log_backend)
Log.setup(loglevel, log_backend)

# Define top level loggers for workload, platform and setup tasks.
# Modules and Classes should have their own loggers.
WLog = Log.for("Workload")
PLog = Log.for("Platform")
SLog = Log.for("Setup")

private def log_backend
  if ENV.has_key?("LOGPATH") || ENV.has_key?("LOG_PATH")
    log_file = ENV.has_key?("LOGPATH") ? ENV["LOGPATH"] : ENV["LOG_PATH"]
  else
    log_file = ""
  end

  if log_file.empty?
    backend = Log::IOBackend.new(formatter: log_formatter)
  else
    log_io = File.open(log_file, "a")
    backend = Log::IOBackend.new(io: log_io, formatter: log_formatter)
  end

  backend
end

private def log_formatter
  Log::Formatter.new do |entry, io|
    progname = "CNTI"
    label = entry.severity.none? ? "ANY" : entry.severity.to_s.upcase
    msg = entry.source.empty? ? "#{progname}: #{entry.message}" : "#{progname}-#{entry.source}: #{entry.message}"
    timestamp = entry.timestamp.to_s("%Y-%m-%d %H:%M:%S")
    io << "[" << timestamp << "] "
    io << label.rjust(6) << " -- " << msg
  end
end

private def loglevel
  level_str = "" # default to unset

  # of course last setting wins so make sure to keep the precendence order desired
  # currently
  #
  # 1. Cli flag is highest precedence
  # 2. Environment var is next level of precedence
  # 3. Config file is last level of precedence

  # lowest priority is first
  if File.exists?(BASE_CONFIG)
    config = Totem.from_file BASE_CONFIG
    if config["loglevel"].as_s?
      level_str = config["loglevel"].as_s
    end
  end

  if ENV.has_key?("LOGLEVEL")
    level_str = ENV["LOGLEVEL"]
  end

  if ENV.has_key?("LOG_LEVEL")
    level_str = ENV["LOG_LEVEL"]
  end

  # highest priority is last
  if !CLILogLevel.level.empty?
    level_str = CLILogLevel.level
  end

  if Log::Severity.parse?(level_str)
    Log::Severity.parse(level_str)
  else
    if !level_str.empty?
      Log.error { "Invalid logging level set. defaulting to ERROR" }
    end
    # if nothing set but also nothing missplled then silently default to error
    Log::Severity::Error
  end
end
