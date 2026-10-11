# What happens when the run is told to stop: SIGTERM from a CI runner's
# cancel, the MCP server's cancel_run or a kill, SIGINT from the terminal.
# Without this the process just died: the results file stayed `running` with
# no exit code, so a reader could not tell a stopped run from one still going,
# and the test under way left what it had created (a chaos engine with its
# fault, a cordoned node) in the cluster (#2713).
#
# A test that changes the cluster registers how to undo it while the change
# is in force; the stop runs every undo still registered, records the test
# under way as an error, finalizes the results file as `stopped` with the
# conventional exit code (128 + the signal), and exits.
module RunStop
  Log = ::Log.for("RunStop")

  @@cleanups = {} of String => Proc(Nil)
  @@current : CNFManager::TestCaseResult? = nil
  @@stopping = false

  # The test under way, so a stop can record it.
  def self.current=(result : CNFManager::TestCaseResult?)
    @@current = result
  end

  def self.current : CNFManager::TestCaseResult?
    @@current
  end

  # Registers how to undo a change the running test made to the cluster; the
  # test calls `done` once it has undone it itself.
  def self.register(key : String, &cleanup : -> Nil)
    @@cleanups[key] = cleanup
  end

  def self.done(key : String)
    @@cleanups.delete(key)
  end

  def self.pending : Array(String)
    @@cleanups.keys
  end

  # Runs every registered undo, each on its own: one that fails does not stop
  # the others. Returns what was run.
  def self.run_cleanups : Array(String)
    ran = [] of String
    @@cleanups.keys.each do |key|
      begin
        @@cleanups[key].call
        ran << key
      rescue ex
        Log.error { "cleanup '#{key}' failed: #{ex.message.to_s.lines.first?}" }
      end
      @@cleanups.delete(key)
    end
    ran
  end

  # The test under way ends as an error naming the signal; tests not reached
  # are simply absent from the results, as after any early end.
  def self.record_stopped_test(signal : Signal) : String?
    result = @@current || return nil
    result.error("run stopped by #{signal_name(signal)}")
    result.set_end_time
    CNFManager::Points.upsert_task(result)
    @@current = nil
    result.testcase
  end

  def self.signal_name(signal : Signal) : String
    "SIG#{signal.to_s.upcase}"
  end

  # Installs the handlers; a second signal while stopping ends the process at
  # once, so a hung cleanup cannot keep it alive.
  def self.install_traps
    {Signal::TERM, Signal::INT}.each do |signal|
      signal.trap { stop(signal) }
    end
  end

  def self.stop(signal : Signal)
    if @@stopping
      Log.warn { "#{signal_name(signal)} again while stopping: exiting now" }
      exit 128 + signal.value
    end
    @@stopping = true
    name = signal_name(signal)
    Log.warn { "#{name} received: stopping the run" }
    stdout_warning "#{name} received: stopping the run"
    cleaned = run_cleanups
    cleaned.each { |key| stdout_info "  undone: #{key}" }
    code = 128 + signal.value
    if CNFManager::Points::Results.file_exists?
      if test = record_stopped_test(signal)
        stdout_info "  #{test}: recorded as an error (run stopped by #{name})"
      end
      CNFManager::Points.stop_results!(signal)
      stdout_info "Results: #{CNFManager::Points::Results.file} (status stopped, exit code #{code})"
    end
    exit code
  end
end
