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

describe "LitmusManager skipped experiments" do
  engine = {
    metadata: {name: "amf-915fea25"},
    status:   {engineStatus: "completed", experiments: [{name: "disk-fill", runner: "amf-915fea25-runner", status: "Skipped", verdict: "Fail", experimentPod: "N/A"}]},
  }.to_json
  ran = {status: {engineStatus: "completed", experiments: [{name: "disk-fill", runner: "amf-1-runner", status: "Completed", verdict: "Pass"}]}}.to_json

  it "names the runner of an experiment litmus skipped", tags: ["points"] do
    LitmusManager.skipped_experiment?(engine).should eq("amf-915fea25-runner")
    LitmusManager.skipped_experiment?(ran).should be_nil
    LitmusManager.skipped_experiment?("{}").should be_nil
    LitmusManager.skipped_experiment?("not json").should be_nil
  end

  it "reads the engine status", tags: ["points"] do
    LitmusManager.engine_status(engine).should eq("completed")
    LitmusManager.engine_status({status: {engineStatus: "initialized"}}.to_json).should eq("initialized")
    LitmusManager.engine_status("").should be_nil
  end

  it "keeps the events about the engine and its runner, oldest first", tags: ["points"] do
    events = JSON.parse({
      items: [
        {involvedObject: {kind: "ChaosEngine", name: "amf-915fea25"}, reason: "ExperimentSkipped", message: "Experiment Job creation failed, skipping Chaos Experiment: disk-fill\nmore", lastTimestamp: "2026-10-04T06:19:38Z"},
        {involvedObject: {kind: "Pod", name: "other-pod"}, reason: "Pulled", message: "irrelevant", lastTimestamp: "2026-10-04T06:19:00Z"},
        {involvedObject: {kind: "Pod", name: "amf-915fea25-runner"}, reason: "Scheduled", message: "Successfully assigned", lastTimestamp: "2026-10-04T06:13:10Z"},
      ],
    }.to_json)
    lines = LitmusManager.skip_events(events, "amf-915fea25", "amf-915fea25-runner")
    lines.should eq([
      "event Pod/amf-915fea25-runner: Scheduled: Successfully assigned",
      "event ChaosEngine/amf-915fea25: ExperimentSkipped: Experiment Job creation failed, skipping Chaos Experiment: disk-fill",
    ])
  end

  it "hands the skipped experiments over once", tags: ["points"] do
    LitmusManager.take_skipped.should eq([] of String)
  end
end
