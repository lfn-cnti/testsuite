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

  it "reports why an experiment could not run", tags: ["points"] do
    helper = {source: "pod-dns-error-helper-vwv22", errorCode: "CONTAINER_RUNTIME_ERROR", phase: "PreChaos", reason: "no running target container found"}.to_json
    raw = {status: {experimentStatus: {verdict: "Error", errorOutput: {errorCode: "CONTAINER_RUNTIME_ERROR", reason: helper}}}}.to_json
    LitmusManager.chaos_failure_summary(raw).should eq("error CONTAINER_RUNTIME_ERROR: no running target container found (PreChaos)")

    plain = {status: {experimentStatus: {verdict: "Error", errorOutput: {errorCode: "NON_USER_FRIENDLY_ERROR", reason: "err: exit status 1"}}}}.to_json
    LitmusManager.chaos_failure_summary(plain).should eq("error NON_USER_FRIENDLY_ERROR: err: exit status 1")
  end

  it "names every engine differently", tags: ["points"] do
    names = (1..200).map { LitmusManager.engine_name("upf") }
    names.uniq.size.should eq(200)
    names.first.should match(/^upf-[0-9a-f]{8}$/)
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
