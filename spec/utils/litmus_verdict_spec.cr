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

  it "names the target litmus recorded and the engine's run time", tags: ["points"] do
    chaos_result = {status: {history: {targets: [{name: "coredns-coredns", kind: "deployment", chaosStatus: "targeted"}]}}}.to_json
    engine = {metadata: {creationTimestamp: "2026-09-24T10:00:00Z"}, status: {experiments: [{lastUpdateTime: "2026-09-24T10:01:05Z"}]}}.to_json
    LitmusManager.chaos_run_summary(chaos_result, engine).should eq "target deployment coredns-coredns (targeted), engine ran 65 s"
  end

  it "says when litmus recorded no target and the engine is gone", tags: ["points"] do
    LitmusManager.chaos_run_summary("{}", "").should eq "target not recorded by litmus"
  end
end
