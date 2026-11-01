require "../spec_helper"

private def status(json : String) : JSON::Any
  JSON.parse(json)
end

describe "WorkloadDiagnostics" do
  it "sees a crash loop while the container is running between restarts", tags: ["points"] do
    running = status(%({"name": "app", "ready": false, "restartCount": 5, "state": {"running": {}},
      "lastState": {"terminated": {"exitCode": 1}}}))

    line = WorkloadDiagnostics.crash_loop(running)

    line.should eq("container app crash-looping (restarted 5 times, last exit code 1)")
    WorkloadDiagnostics.crash_looping?(line.not_nil!, "app").should be_true
  end

  it "sees a crash loop while the container has just ended", tags: ["points"] do
    ended = status(%({"name": "app", "ready": false, "restartCount": 5, "state": {"terminated": {"exitCode": 2}},
      "lastState": {"terminated": {"exitCode": 1}}}))

    WorkloadDiagnostics.crash_loop(ended).should eq("container app crash-looping (restarted 5 times, last exit code 2)")
  end

  it "leaves a waiting container to its own reason", tags: ["points"] do
    waiting = status(%({"name": "app", "ready": false, "restartCount": 5, "state": {"waiting": {"reason": "CrashLoopBackOff"}},
      "lastState": {"terminated": {"exitCode": 1}}}))

    WorkloadDiagnostics.crash_loop(waiting).should be_nil
    WorkloadDiagnostics.crash_looping?("container app waiting (CrashLoopBackOff: back-off)", "app").should be_true
  end

  it "does not call one crash, a ready container or a clean exit a crash loop", tags: ["points"] do
    once = status(%({"name": "app", "ready": false, "restartCount": 1, "state": {"running": {}},
      "lastState": {"terminated": {"exitCode": 1}}}))
    recovered = status(%({"name": "app", "ready": true, "restartCount": 5, "state": {"running": {}},
      "lastState": {"terminated": {"exitCode": 1}}}))
    clean = status(%({"name": "app", "ready": false, "restartCount": 5, "state": {"running": {}},
      "lastState": {"terminated": {"exitCode": 0}}}))

    WorkloadDiagnostics.crash_loop(once).should be_nil
    WorkloadDiagnostics.crash_loop(recovered).should be_nil
    WorkloadDiagnostics.crash_loop(clean).should be_nil
    WorkloadDiagnostics.crash_looping?("container app waiting (ImagePullBackOff: back-off)", "app").should be_false
  end

  it "does not take a sidecar's crash loop for the container beside it", tags: ["points"] do
    line = "pod web-0: Running; container app waiting (ImagePullBackOff: back-off); container sidecar crash-looping (restarted 5 times, last exit code 1)"
    waiting = "pod web-0: Running; container app waiting (ImagePullBackOff: back-off); container sidecar waiting (CrashLoopBackOff: back-off)"

    WorkloadDiagnostics.crash_looping?(line, "app").should be_false
    WorkloadDiagnostics.crash_looping?(line, "sidecar").should be_true
    WorkloadDiagnostics.crash_looping?(waiting, "app").should be_false
    WorkloadDiagnostics.crash_looping?(waiting, "sidecar").should be_true
  end
end
