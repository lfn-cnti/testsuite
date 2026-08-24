require "../spec_helper"

describe "LitmusManager.chaos_failure_summary" do
  it "extracts the failStep and every non-passing probe", tags: ["points"] do
    raw = {
      status: {
        experimentStatus: {verdict: "Fail", failStep: "AUT: Running check failed"},
        probeStatuses:    [
          {name: "app-ready", status: {verdict: "Failed", description: "pod not ready after chaos"}},
          {name: "node-back", status: {verdict: "Passed"}},
        ],
      },
    }.to_json

    summary = LitmusManager.chaos_failure_summary(raw).not_nil!
    summary.should contain("failStep: AUT: Running check failed")
    summary.should contain("probe app-ready: Failed (pod not ready after chaos)")
    summary.should_not contain("node-back")
  end

  it "returns nil when there is no detail to report", tags: ["points"] do
    LitmusManager.chaos_failure_summary({status: {experimentStatus: {failStep: "N/A"}}}.to_json).should be_nil
    LitmusManager.chaos_failure_summary("{}").should be_nil
    LitmusManager.chaos_failure_summary("not json at all").should be_nil
  end
end
