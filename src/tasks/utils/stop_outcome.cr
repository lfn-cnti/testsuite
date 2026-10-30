# How sig_term_handled reads a container stop (microservice.cr).
module StopOutcome
  # The signals that ask a process to shut down. A supervisor is free to stop
  # a service with the one it wants (SIGQUIT for nginx, SIGUSR1 for haproxy);
  # any of them delivered by PID 1 is the container's SIGTERM being acted on.
  TERMINATION_SIGNALS = ["SIGTERM", "SIGINT", "SIGQUIT", "SIGHUP", "SIGUSR1", "SIGUSR2"]

  # Whether a process that ended on a signal (its trace ends in "+++ killed
  # by SIG... +++") was killed rather than stopped. A process with no handler
  # for the signal it is asked to stop with ends on that signal's default
  # action: it did what it was asked, promptly, and has stopped. SIGKILL (the
  # runtime ending what outlived the grace period) and a crash (SIGABRT,
  # SIGSEGV) are what fail.
  def self.killed?(killed_by : String?) : Bool
    !killed_by.nil? && !TERMINATION_SIGNALS.includes?(killed_by)
  end

  # The survivors once the runtime's kill is counted. The judged processes
  # are checked until the grace period runs out, and the runtime kills the
  # container just after it: whether the last check comes before or after
  # that kill is timing, not the CNF. So when the container exited with 137,
  # a process still alive at the deadline whose trace ends in SIGKILL was
  # ended by the runtime, and is reported as killed instead of stopped, not
  # as still running.
  def self.survivors_after_runtime_kill(survivors : Array(String),
                                        endings : Hash(String, NamedTuple(signal: String?, killed_by: String?)),
                                        exit_code : Int32?) : Array(String)
    return survivors unless exit_code == 137
    survivors.reject { |cpid| endings[cpid]?.try(&.[:killed_by]) == "SIGKILL" }
  end
end
