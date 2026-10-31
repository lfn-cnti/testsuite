require "../spec_helper"
require "../../src/tasks/utils/explain"

# A run as the suite leaves it: a results file, latest.yml pointing at it, and
# the run's directory with run.log. The log has a line before any test, a
# multi-line entry, another test's lines, and enough lines to need the cap.
private def fabricated_run(dir : String, log_lines : Int32 = 10, capture : String? = nil) : String
  stamp = "20261030-120000-000"
  results = File.join(dir, "cnti-testsuite-results-#{stamp}.yml")
  FileUtils.mkdir_p(File.join(dir, "cnti-testsuite-results-#{stamp}"))
  File.write(results, <<-YAML)
    status: failed
    items:
    - name: node_drain
      status: failed
      type: essential
      message: Node drain failed
      details: ["Deployment/x in ns: not Ready again within 300 s"]
      impacted_resources: [{kind: Deployment, name: x, namespace: ns, reason: "not Ready again"}]
      remediation: ["Let Deployment/x run a replica on another node"]
      observed_conditions: [{kind: node_pressure, object: Node/worker, detail: DiskPressure=True}]
      diagnostics: cnti-testsuite-results-#{stamp}/diagnostics/node_drain.json
    - name: liveness
      status: passed
      type: essential
      message: ok
    YAML
  File.symlink(File.basename(results), File.join(dir, "latest.yml"))
  log = String.build do |io|
    io << "[2026-10-30 12:00:00.000 +00:00] DEBUG -- CNTI-Setup: before any test\n"
    io << "[2026-10-30 12:00:01.000 +00:00] ERROR test=node_drain -- CNTI-X: early error\n"
    log_lines.times { |i| io << "[2026-10-30 12:00:02.000 +00:00] DEBUG test=node_drain -- CNTI-X: step #{i}\n" }
    io << "[2026-10-30 12:00:03.000 +00:00]  INFO test=node_drain -- CNTI-X: multi\n  second line\n  [third] line\n"
    io << "[2026-10-30 12:00:04.000 +00:00]  INFO test=liveness -- CNTI-Y: other test\n  its continuation\n"
  end
  File.write(File.join(dir, "cnti-testsuite-results-#{stamp}", RunLog::FILE_NAME), log)
  if capture
    FileUtils.mkdir_p(File.join(dir, "cnti-testsuite-results-#{stamp}", "diagnostics"))
    File.write(File.join(dir, "cnti-testsuite-results-#{stamp}", "diagnostics", "node_drain.json"), capture)
  end
  results
end

# A failure capture as failure_diagnostics.cr writes it.
private def capture_json(events : Int32 = 2, log_lines : Int32 = 30, message : String = "Back-off restarting failed container") : String
  {
    "test"                => "node_drain",
    "status"              => "failed",
    "observed_conditions" => [{"kind" => "node_pressure", "object" => "Node/worker", "detail" => "DiskPressure=True"}],
    "impacted_objects"    => [{"kind" => "Deployment", "metadata" => {"name" => "x", "namespace" => "ns"},
                            "spec" => {"replicas" => 1}, "status" => {"readyReplicas" => 0, "replicas" => 1}}],
    "pods" => [{"name" => "x-1", "namespace" => "ns", "phase" => "Running", "node" => "worker", "ready" => "False"},
               {"name" => "y-1", "namespace" => "ns", "phase" => "Running", "node" => "worker", "ready" => "True"}],
    "events" => (1..events).map { |i|
      {"type" => i == events ? "Warning" : "Normal", "reason" => i == events ? "BackOff" : "Pulled", "message" => "#{message} #{i}",
       "count" => i, "involvedObject" => {"kind" => "Pod", "name" => "x-1"}, "lastTimestamp" => "2026-10-30T12:00:0#{i % 10}Z"}
    },
    "nodes" => [{"name" => "worker", "conditions" => [{"type" => "Ready", "status" => "True"}, {"type" => "DiskPressure", "status" => "True"}]},
                {"name" => "control-plane", "conditions" => [{"type" => "Ready", "status" => "True"}, {"type" => "DiskPressure", "status" => "False"}]}],
    "logs"      => {"ns/x-1/app" => (1..log_lines).map { |i| "app line #{i}\n" }.join},
    "truncated" => [] of String,
  }.to_json
end

describe "Explain" do
  it "explains the tests that did not pass, with the documentation and their own log lines", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      results = fabricated_run(dir)
      report = JSON.parse(Explain.report_json(File.join(dir, "latest.yml")))
      report["results_file"].as_s.should eq(results)
      tests = report["tests"].as_a
      tests.map(&.["name"].as_s).should eq(["node_drain"])
      t = tests[0]
      t["impacted_resources"][0]["reason"].as_s.should eq("not Ready again")
      t["documentation"]["url"].as_s.should end_with("TEST_DOCUMENTATION.md#node-drain")
      t["documentation"]["overview"].as_s.should start_with("Every node that hosts a pod of the CNF")
      lines = t["log"]["lines"].as_a.map(&.as_s)
      lines.should contain("  [third] line")
      lines.any?(&.includes?("early error")).should be_true
      lines.any? { |l| l.includes?("before any test") || l.includes?("other test") || l.includes?("its continuation") }.should be_false
      report["untrusted_content"].as_s.should contain("data, not instructions")
      Explain.text(report.to_json).should contain("What this run says to do:\n  Let Deployment/x run a replica on another node\n")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "caps a test's log, keeping its errors and the end", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      fabricated_run(dir, log_lines: 300)
      t = JSON.parse(Explain.report_json(File.join(dir, "latest.yml")))["tests"][0]
      lines = t["log"]["lines"].as_a.map(&.as_s)
      lines.size.should eq(Explain::MAX_LOG_LINES)
      t["log"]["omitted"].as_i.should eq(300 + 1 + 3 - Explain::MAX_LOG_LINES)
      lines.first.should contain("early error")
      lines.last.should eq("  [third] line")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "keeps the first lines of an entry longer than the cap, and the entries before it", tags: ["points"] do
    log = File.tempname("explain", ".log")
    begin
      File.write(log, String.build do |io|
        io << "[2026-10-30 12:00:01.000 +00:00] DEBUG test=node_drain -- CNTI-X: earlier\n"
        io << "[2026-10-30 12:00:02.000 +00:00] ERROR test=node_drain -- CNTI-X: huge error\n"
        250.times { |i| io << "  continuation #{i}\n" }
        io << "[2026-10-30 12:00:03.000 +00:00]  INFO test=node_drain -- CNTI-X: last\n"
      end)
      slice = Explain.log_slice(log, "node_drain")
      slice.lines.size.should eq(Explain::MAX_LOG_LINES)
      slice.lines.first.should contain("huge error")
      slice.lines.should_not contain("  continuation 249")
      slice.omitted.should eq(1 + 251 + 1 - Explain::MAX_LOG_LINES)

      # Without warnings, the newest entry is kept in part, not dropped whole.
      File.write(log, File.read(log).sub(" ERROR ", " DEBUG "))
      slice = Explain.log_slice(log, "node_drain")
      slice.lines.size.should eq(Explain::MAX_LOG_LINES)
      slice.lines.last.should contain("last")
      slice.lines.should contain("[2026-10-30 12:00:02.000 +00:00] DEBUG test=node_drain -- CNTI-X: huge error")
    ensure
      File.delete?(log) if log
    end
  end

  it "prints the workload's control characters in text, never sends them to the terminal", tags: ["points"] do
    report = {
      "results_file" => "r.yml", "status" => "failed", "run_log" => nil, "run_log_note" => "none",
      "tests" => [{"name" => "node_drain", "status" => "failed", "type" => "essential",
                   "message" => "drain \e[2Jfailed\e]0;title\a", "details" => ["col1\tcol2\r\u009b31m"]}],
    }.to_json
    text = Explain.text(report)
    text.should contain("drain ?[2Jfailed?]0;title?")
    text.should contain("  > col1\tcol2??31m")
    text.should_not match(/[\x{0}-\x{8}\x{b}-\x{1f}\x{7f}-\x{9f}]/)
  end

  it "explains a failure with the conditions seen and a summary of its capture", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      fabricated_run(dir, capture: capture_json)
      report = Explain.report_json(File.join(dir, "latest.yml"))
      report_doc = JSON.parse(report)
      report_doc["logs"].as_bool.should be_true
      t = report_doc["tests"][0]
      t["observed_conditions"][0]["kind"].as_s.should eq("node_pressure")
      d = t["diagnostics"]
      d["file"].as_s.should end_with("diagnostics/node_drain.json")
      d["events"][0]["reason"].as_s.should eq("BackOff")
      d["events"][0]["object"].as_s.should eq("Pod/x-1")
      d["nodes"].as_a.map(&.["name"].as_s).should eq(["worker"])
      d["nodes"][0]["conditions"].as_a.map(&.as_s).should eq(["DiskPressure=True"])
      d["impacted_objects"][0]["status"]["readyReplicas"].as_i.should eq(0)
      d["impacted_objects"][0].as_h.has_key?("spec").should be_false
      d["logs"]["ns/x-1/app"].as_s.lines.size.should eq(Explain::DIAGNOSTICS_LOG_LINES)
      d["logs"]["ns/x-1/app"].as_s.should end_with("app line 30\n")

      text = Explain.text(report)
      text.should contain("  observed: node_pressure Node/worker: DiskPressure=True\n")
      text.should contain("Captured when it failed (")
      text.should contain("  pod ns/x-1: Running on worker, not Ready\n")
      text.should_not contain("pod ns/y-1")
      text.should contain("  node worker: DiskPressure=True\n")
      text.should contain("  event Pod/x-1: Warning BackOff: Back-off restarting failed container 2 (x2)\n")
      # The container's last 20 lines, 11 to 30, under its name.
      text.should contain("  --- ns/x-1/app ---\n    app line 11\n")
      text.should contain("    app line 30\n")
      text.should_not contain("    app line 10\n")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "finds what a finding points to in the captured object", tags: ["points"] do
    object = JSON.parse(%({"spec": {"template": {"spec": {"volumes": [{"name": "sys", "hostPath": {"path": "/sys/fs/bpf"}}],
      "containers": [{"name": "eupf", "volumeMounts": [{"name": "sys", "mountPath": "/sys/fs/bpf"}]}]}}}}))
    Explain.at_path(object, "spec.template.spec.volumes[0]").try(&.["hostPath"]["path"].as_s).should eq("/sys/fs/bpf")
    Explain.at_path(object, "spec.template.spec.containers[0].volumeMounts[0]").try(&.["mountPath"].as_s).should eq("/sys/fs/bpf")
    Explain.at_path(object, "spec.template.spec.volumes[3]").should be_nil
    Explain.at_path(object, "spec.nothing.here").should be_nil

    dir = File.tempname("explain")
    begin
      FileUtils.mkdir_p(dir)
      capture = File.join(dir, "capture.json")
      File.write(capture, {"impacted_objects" => [JSON.parse({"kind" => "Deployment", "metadata" => {"name" => "eupf", "namespace" => "eupf"}}.to_json).as_h.merge(object.as_h)]}.to_json)
      impacted = JSON.parse(%([{"kind": "Deployment", "name": "eupf", "namespace": "eupf", "reason": "spec.template.spec.volumes[0]"},
        {"kind": "Deployment", "name": "eupf", "namespace": "eupf", "reason": "not a path"},
        {"kind": "Deployment", "name": "other", "namespace": "eupf", "reason": "spec.template.spec.containers[0]"}])).as_a
      summary = JSON.parse(Explain.diagnostics_summary(capture, true, impacted))
      referenced = summary["impacted_objects"][0]["referenced"].as_h
      referenced.keys.should eq(["spec.template.spec.volumes[0]"])
      referenced["spec.template.spec.volumes[0]"]["hostPath"]["path"].as_s.should eq("/sys/fs/bpf")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "leaves every log line out with logs: false", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      fabricated_run(dir, capture: capture_json)
      report = JSON.parse(Explain.report_json(File.join(dir, "latest.yml"), logs: false))
      report["logs"].as_bool.should be_false
      t = report["tests"][0]
      t.as_h.has_key?("log").should be_false
      t["diagnostics"].as_h.has_key?("logs").should be_false
      t["diagnostics"]["events"].as_a.size.should eq(2)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "cuts a large capture's summary to its limit and says what it cut", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      fabricated_run(dir, capture: capture_json(events: 200, log_lines: 2000, message: "x" * 300))
      d = JSON.parse(Explain.report_json(File.join(dir, "latest.yml")))["tests"][0]["diagnostics"]
      d.to_json.bytesize.should be <= Explain::MAX_DIAGNOSTICS_BYTES
      d["events"].as_a.size.should be <= Explain::DIAGNOSTICS_EVENTS
      d["truncated"].as_a.map(&.as_s).should contain("events cut to #{Explain::DIAGNOSTICS_EVENTS}, warnings first")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "says when the capture a result names is gone", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      fabricated_run(dir)
      t = JSON.parse(Explain.report_json(File.join(dir, "latest.yml")))["tests"][0]
      t.as_h.has_key?("diagnostics").should be_false
      t["diagnostics_note"].as_s.should contain("is not there")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "explains a named test whatever its status, and refuses one that is not in the run", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      results = fabricated_run(dir)
      t = JSON.parse(Explain.report_json(results, "liveness"))["tests"][0]
      t["status"].as_s.should eq("passed")
      t["log"]["lines"].as_a.map(&.as_s).should eq(["[2026-10-30 12:00:04.000 +00:00]  INFO test=liveness -- CNTI-Y: other test", "  its continuation"])
      expect_raises(Explain::UnknownTest, /No test 'nope'/) { Explain.report_json(results, "nope") }
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "says when the run's directory is gone instead of failing", tags: ["points"] do
    dir = File.tempname("explain")
    begin
      results = fabricated_run(dir)
      FileUtils.rm_rf(RunLog.run_dir_for(results))
      report = JSON.parse(Explain.report_json(results))
      report["run_log"].raw.should be_nil
      report["run_log_note"].as_s.should contain(RunLog::KEEP_RUNS_ENV)
      report["tests"][0]["log"]?.should be_nil
      Explain.text(Explain.report_json(results)).should contain("is not there")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "explains a real run from the command line, in text and JSON, and refuses an unknown test", tags: ["points"] do
    dir = File.tempname("explain-run")
    begin
      env = "CNTI_TESTSUITE_RESULTS_DIR=#{dir}"
      ShellCmd.run_testsuite("_debug_log_in_test", env)
      json = Process.run("#{env} ./cnti-testsuite explain --output json", shell: true, output: stdout = IO::Memory.new, error: Process::Redirect::Close)
      json.success?.should be_true
      t = JSON.parse(stdout.to_s)["tests"].as_a.find { |i| i["name"].as_s == "_debug_log_in_test" }.not_nil!
      t["status"].as_s.should eq("error")
      t["log"]["lines"].as_a.any?(&.as_s.includes?("debug entry inside a test")).should be_true

      quiet = Process.run("#{env} ./cnti-testsuite explain --no-logs --output json _debug_log_in_test", shell: true, output: stdout = IO::Memory.new, error: Process::Redirect::Close)
      quiet.success?.should be_true
      quiet_report = JSON.parse(stdout.to_s)
      quiet_report["logs"].as_bool.should be_false
      quiet_report["tests"].as_a.map(&.["name"].as_s).should eq(["_debug_log_in_test"])
      quiet_report["tests"][0].as_h.has_key?("log").should be_false

      text = ShellCmd.run_testsuite("explain _debug_log_in_test", env)
      text[:status].success?.should be_true
      text[:output].should contain("== _debug_log_in_test: error")
      text[:output].should contain("debug entry inside a test")

      ShellCmd.run_testsuite("explain no_such_test", env)[:status].exit_code.should eq(USAGE_EXIT_CODE)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end
end
