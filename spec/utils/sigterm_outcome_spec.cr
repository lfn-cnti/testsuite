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
