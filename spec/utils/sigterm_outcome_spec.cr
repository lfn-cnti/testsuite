require "../spec_helper"
require "../../src/tasks/utils/stop_outcome.cr"

# sig_term_handled checks the judged processes until the grace period runs
# out; the runtime kills the container just after. A process the runtime
# killed is reported as killed whichever side of the deadline the last check
# fell on.
describe "StopOutcome.survivors_after_runtime_kill" do
  endings = Hash(String, NamedTuple(signal: String?, killed_by: String?)){
    "11" => {signal: "SIGTERM", killed_by: "SIGKILL"},
    "12" => {signal: nil, killed_by: nil},
  }

  it "counts a deadline survivor the runtime killed as killed", tags: ["sig_term"] do
    StopOutcome.survivors_after_runtime_kill(["11", "12"], endings, 137).should eq(["12"])
  end

  it "keeps the survivors when the runtime did not kill the container", tags: ["sig_term"] do
    StopOutcome.survivors_after_runtime_kill(["11", "12"], endings, 0).should eq(["11", "12"])
    StopOutcome.survivors_after_runtime_kill(["11"], endings, nil).should eq(["11"])
  end
end

# A process with no handler for the stop signal ends on its default action
# ("+++ killed by SIGTERM +++"): that is stopping. SIGKILL and a crash are not.
describe "StopOutcome.killed?" do
  it "counts a process ended by a termination signal's default action as stopped", tags: ["sig_term"] do
    StopOutcome::TERMINATION_SIGNALS.each { |signal| StopOutcome.killed?(signal).should be_false }
    StopOutcome.killed?(nil).should be_false
  end

  it "counts SIGKILL and a crash as killed", tags: ["sig_term"] do
    StopOutcome.killed?("SIGKILL").should be_true
    StopOutcome.killed?("SIGABRT").should be_true
    StopOutcome.killed?("SIGSEGV").should be_true
  end
end
