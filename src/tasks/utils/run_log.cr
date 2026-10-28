require "log"
require "file_utils"

# The run's own debug log (#2807): every entry at debug level and above, whatever
# the console's level, kept next to the results file in a directory of the same
# name (`cnti-testsuite-results-<timestamp>/run.log`). The detail of a failed run
# then exists without running it again with `-l debug`, when the cluster state is
# gone or the failure does not come back.
#
# Logging starts before the run has a results file, and most invocations never
# get one (help, evidence, results_junit), so entries are held in memory until
# the results file is created, then written to run.log and from there on
# appended to it. An invocation that ends without a results file drops them,
# unless it prepares a run in a process of its own: `setup` and `cnf_install`
# write `pending/<task>-<timestamp>.log` in the results directory, and the next
# run that creates a results file moves those logs into its directory, so the
# install that preceded a run is read with it.
module RunLog
  FILE_NAME   = "run.log"
  PENDING_DIR = "pending"
  # The tasks whose log waits for the run that follows them.
  PREPARING_TASKS = ["setup", "cnf_install"]

  MAX_FILE_BYTES   = 50 * 1024 * 1024
  MAX_BUFFER_BYTES = 8 * 1024 * 1024

  KEEP_RUNS_ENV     = "CNTI_TESTSUITE_KEEP_RUNS"
  DEFAULT_KEEP_RUNS = 5
  RUN_DIR_GLOB      = "cnti-testsuite-results-*"

  class Backend < ::Log::Backend
    @buffer = IO::Memory.new
    @buffer_full = false
    @file : File? = nil
    @file_bytes = 0_i64
    @file_full = false
    @run_dir : String? = nil
    # Set once the log has nowhere to go: entries are dropped from then on.
    @closed = false
    @mutex = Mutex.new

    def initialize
      # Synchronous, so the entries written before an exit are on disk.
      super(::Log::DispatchMode::Sync)
    end

    def write(entry : ::Log::Entry)
      line = String.build { |io| RunLog.format(entry, io) }
      @mutex.synchronize { append(line) }
    end

    getter run_dir

    # From now on the log is written to *path*, after what was held so far.
    def write_to(path : String, run_dir : String? = nil) : Nil
      @mutex.synchronize do
        return if @closed
        close_file
        file = File.new(path, "a")
        file.sync = true
        @file = file
        @file_bytes = file.size
        @file_full = false
        @run_dir = run_dir
        held = @buffer.to_s
        @buffer = IO::Memory.new
        append(held) unless held.empty?
      end
    end

    # Ends the file being written, if any; later entries are held again.
    def detach : Nil
      @mutex.synchronize { close_file }
    end

    # Drops what was held and everything after it.
    def discard : Nil
      @mutex.synchronize do
        close_file
        @buffer = IO::Memory.new
        @closed = true
      end
    end

    private def close_file
      @file.try(&.close)
      @file = nil
      @run_dir = nil
    end

    private def append(text : String)
      return if @closed
      if file = @file
        return if @file_full
        begin
          if @file_bytes + text.bytesize > MAX_FILE_BYTES
            file << "[run.log truncated at #{MAX_FILE_BYTES // (1024 * 1024)} MB: later entries are not kept]\n"
            @file_full = true
            return
          end
          file << text
          @file_bytes += text.bytesize
        rescue IO::Error
          # A full disk or a file gone: the debug log stops, the run goes on.
          @file_full = true
        end
      else
        return if @buffer_full
        if @buffer.bytesize + text.bytesize > MAX_BUFFER_BYTES
          @buffer << "[run.log truncated at #{MAX_BUFFER_BYTES // (1024 * 1024)} MB before the run had a results file: later entries are not kept until it has one]\n"
          @buffer_full = true
          return
        end
        @buffer << text
      end
    end
  end

  class_getter backend = Backend.new

  @@results_dir : String? = nil
  @@pending : String? = nil

  # One entry per line, continuation lines indented, so a reader tells entries
  # apart even when a message spans lines: `[time] LEVEL test=<name> -- source: message`.
  # `test=` is there while a test runs (the `test` key of the log context).
  def self.format(entry : ::Log::Entry, io : IO) : Nil
    label = entry.severity.none? ? "ANY" : entry.severity.to_s.upcase
    io << '[' << entry.timestamp.to_s("%Y-%m-%d %H:%M:%S.%L %:z") << "] " << label.rjust(5)
    if test = entry.context[:test]?
      io << " test=" << test
    end
    io << " -- CNTI"
    io << '-' << entry.source unless entry.source.empty?
    io << ": "
    message = entry.message
    if ex = entry.exception
      message = String.build do |text|
        text << message << '\n' << ex.class.name << ": " << ex.message
        ex.backtrace?.try &.each { |frame| text << '\n' << frame }
      end
    end
    message.each_line(chomp: true).each_with_index do |line, index|
      io << "\n  " unless index == 0
      io << line
    end
    io << '\n'
  end

  # Called once the command line is parsed: where the results go, and whether
  # this invocation prepares a run whose log should wait for it.
  def self.start(results_dir : String, tasks : Array(String)) : Nil
    @@results_dir = results_dir
    if task = tasks.find { |name| PREPARING_TASKS.includes?(name) }
      pending_dir = File.join(results_dir, PENDING_DIR)
      FileUtils.mkdir_p(pending_dir)
      path = File.join(pending_dir, "#{task}-#{Time.local.to_s("%Y%m%d-%H%M%S-%L")}.log")
      backend.write_to(path)
      @@pending = path
    end
  rescue ex : IO::Error
    Log.for("RunLog").warn { "The run's debug log is not kept: #{ex.message}" }
    backend.discard
  end

  # The directory of the run whose results file is *results_file*.
  def self.run_dir_for(results_file : String) : String
    results_file.rchop(".yml")
  end

  # The run has its results file: its directory gets the logs of the preparing
  # invocations before it, then run.log with everything logged so far. Older
  # run directories beyond the retention are removed.
  def self.attach(results_file : String) : Nil
    run_dir = run_dir_for(results_file)
    return if backend.run_dir == run_dir
    backend.detach
    @@pending = nil
    FileUtils.mkdir_p(run_dir)
    adopt_pending(File.dirname(results_file), run_dir)
    backend.write_to(File.join(run_dir, FILE_NAME), run_dir)
    prune(File.dirname(results_file), keep_runs)
  rescue ex : IO::Error
    backend.discard
    Log.for("RunLog").warn { "The run's debug log is not kept: #{ex.message}" }
  end

  # Moves the logs waiting in the results directory's pending/ into *run_dir*.
  def self.adopt_pending(results_dir : String, run_dir : String) : Nil
    pending_dir = File.join(results_dir, PENDING_DIR)
    return unless Dir.exists?(pending_dir)
    Dir.children(pending_dir).sort.each do |name|
      next unless name.ends_with?(".log")
      File.rename(File.join(pending_dir, name), File.join(run_dir, name))
    end
    Dir.delete(pending_dir) if Dir.empty?(pending_dir)
  end

  # Keeps the newest *keep* run directories in *results_dir*; their names sort
  # by time. Results files are never touched.
  def self.prune(results_dir : String, keep : Int32) : Nil
    runs = Dir.glob(File.join(results_dir, RUN_DIR_GLOB)).select { |path| Dir.exists?(path) && !File.symlink?(path) }.sort
    runs[0, {runs.size - keep, 0}.max].each { |path| FileUtils.rm_rf(path) }
  end

  # How many run directories are kept: CNTI_TESTSUITE_KEEP_RUNS, at least 1.
  def self.keep_runs : Int32
    value = ENV[KEEP_RUNS_ENV]?
    return DEFAULT_KEEP_RUNS if value.nil? || value.empty?
    keep = value.to_i?
    if keep && keep >= 1
      keep
    else
      Log.for("RunLog").warn { "#{KEEP_RUNS_ENV}=#{value} is not a whole number of at least 1; keeping #{DEFAULT_KEEP_RUNS} run directories" }
      DEFAULT_KEEP_RUNS
    end
  end
end
