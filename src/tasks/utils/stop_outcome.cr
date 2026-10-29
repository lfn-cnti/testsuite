# How sig_term_handled reads a container stop (microservice.cr).
module StopOutcome
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
