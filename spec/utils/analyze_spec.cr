require "../spec_helper"
require "../../src/tasks/utils/analyze"

# A run as the suite leaves it, with two failed tests and one passed:
# node_drain with an impacted resource, an observed condition and a capture
# of the cluster; zombie_handled with an impacted resource only.
private def analyze_run(dir : String, events : Int32 = 2) : String
  stamp = "20261031-120000-000"
  run_dir = File.join(dir, "cnti-testsuite-results-#{stamp}")
  FileUtils.mkdir_p(File.join(run_dir, "diagnostics"))
  results = File.join(dir, "cnti-testsuite-results-#{stamp}.yml")
  File.write(results, <<-YAML)
    testsuite_version: v2.4.0
    status: failed
    tools:
      litmus: 3.20.0
    items:
    - name: node_drain
      status: failed
      type: essential
      message: node_drain failed
      impacted_resources: [{kind: StatefulSet, name: db, namespace: cnf, reason: not Ready within 180s of eviction}]
      observed_conditions: [{kind: scheduling_failed, object: Pod/db-0 in cnf, detail: "2 node(s) didn't match PersistentVolume's node affinity"}]
      diagnostics: cnti-testsuite-results-#{stamp}/diagnostics/node_drain.json
    - name: zombie_handled
      status: failed
      type: essential
      message: Zombie not handled
      impacted_resources: [{kind: Pod, name: db-0, namespace: cnf, container: db, reason: "process sleep (pid 9) is a zombie"}]
    - name: liveness
      status: passed
      type: essential
      message: ok
    YAML
  File.symlink(File.basename(results), File.join(dir, "latest.yml"))
  File.write(File.join(run_dir, RunLog::FILE_NAME), "[2026-10-31 12:00:01.000 +00:00] ERROR test=node_drain -- CNTI-X: drain refused\n")
  File.write(File.join(run_dir, "diagnostics", "node_drain.json"), {
    "test"             => "node_drain",
    "impacted_objects" => [{"kind" => "StatefulSet", "metadata" => {"name" => "db", "namespace" => "cnf"}, "status" => {"readyReplicas" => 0}}],
    "pods"             => [{"name" => "db-0", "namespace" => "cnf", "phase" => "Pending", "ready" => "False"}],
    "events"           => (1..events).map { |i| {"type" => "Warning", "reason" => "FailedScheduling", "message" => "x" * 250 + " #{i}", "involvedObject" => {"kind" => "Pod", "name" => "db-0"}} },
    "nodes"            => [] of String,
    "logs"             => {"cnf/db-0/db" => "starting\n"},
    "truncated"        => [] of String,
  }.to_json)
  results
end

private def options(provider = "anthropic", model = "claude-opus-5-5", endpoint : String? = nil, expected : String? = nil,
                    analyze_expected = false, max_kb = 48, logs = false)
  Analyze::Options.new(provider, model, endpoint, logs, max_kb * 1024, expected, analyze_expected)
end

private def reply(dir : String, body) : String
  path = File.join(dir, "response.json")
  File.write(path, body.to_json)
  path
end

private def anthropic_answer(readings) : Hash(String, JSON::Any)
  {"model" => JSON::Any.new("claude-opus-5-5"), "stop_reason" => JSON::Any.new("end_turn"),
   "content" => JSON.parse([{"type" => "text", "text" => {"tests" => readings}.to_json}].to_json)}
end

private def reading(name : String, cited : Array(String), confidence = "high")
  {"name" => name, "likely_cause" => "the volume is tied to the drained node", "supported_by" => cited,
   "confidence" => confidence, "next_step" => {"kind" => "check_runner_or_cluster", "detail" => "storage that follows a pod"}}
end

describe "Analyze" do
  it "prepares an Anthropic request with every fact cited by id, and no key", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      Analyze.prepare(File.join(dir, "latest.yml"), options, outdir).should be_true
      body = JSON.parse(File.read(File.join(outdir, "request.json")))
      body["model"].as_s.should eq("claude-opus-5-5")
      body["system"].as_s.should eq(Analyze::PROMPT)
      body["output_config"]["format"]["type"].as_s.should eq("json_schema")
      body["fallbacks"].as_s.should eq("default")
      user = body["messages"][0]["content"].as_s
      user.should contain("<cnti_facts>")
      user.should contain(%("id":"T1-M"))
      user.should contain(%("id":"T1-R1"))
      user.should contain(%("id":"T1-C1"))
      user.should contain(%("id":"T1-E1"))
      user.should contain(%("id":"T2-R1"))
      user.should contain(%("testsuite_version":"v2.4.0"))
      File.read(File.join(outdir, "request.headers")).should contain("anthropic-version: #{Analyze::ANTHROPIC_VERSION}\nanthropic-beta: #{Analyze::FALLBACK_BETA}")
      env = File.read(File.join(outdir, "request.env"))
      env.should contain("URL='#{Analyze::ANTHROPIC_URL}'")
      env.should contain("KEY_HEADER='x-api-key'")
      state = JSON.parse(File.read(File.join(outdir, "state.json")))
      state["facts"]["T1-R1"].as_s.should eq("StatefulSet/db in cnf: not Ready within 180s of eviction")
      state["facts"]["T1-C1"].as_s.should eq("scheduling_failed Pod/db-0 in cnf: 2 node(s) didn't match PersistentVolume's node affinity")
      state["facts"]["T2-R1"].as_s.should eq("Pod/db-0 in cnf (container db): process sleep (pid 9) is a zombie")
      state["tests"].as_a.map(&.["name"].as_s).should eq(["node_drain", "zombie_handled"])

      # Through a proxy of one's own, or with a model without it: no fallback.
      Analyze.prepare(results, options(model: "claude-haiku-5-5"), outdir)
      JSON.parse(File.read(File.join(outdir, "request.json"))).as_h.has_key?("fallbacks").should be_false
      Analyze.prepare(results, options(endpoint: "https://proxy.example/"), outdir)
      File.read(File.join(outdir, "request.env")).should contain("URL='https://proxy.example/v1/messages'")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "prepares an OpenAI-compatible request, and the same without response_format for a server that refuses it", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      Analyze.prepare(results, options(provider: "openai-compatible", model: "qwen2.5:3b", endpoint: "http://127.0.0.1:11434/v1"), outdir)
      body = JSON.parse(File.read(File.join(outdir, "request.json")))
      body["response_format"]["json_schema"]["schema"]["required"].as_a.map(&.as_s).should eq(["tests"])
      body["messages"][0]["content"].as_s.should contain("The JSON object follows this JSON Schema")
      JSON.parse(File.read(File.join(outdir, "request.retry.json"))).as_h.has_key?("response_format").should be_false
      env = File.read(File.join(outdir, "request.env"))
      env.should contain("URL='http://127.0.0.1:11434/v1/chat/completions'")
      env.should contain("KEY_PREFIX='Bearer '")
      expect_raises(Analyze::Error, /needs --endpoint/) { Analyze.prepare(results, options(provider: "openai-compatible"), outdir) }
      expect_raises(Analyze::Error, /no provider/) { Analyze.prepare(results, options(provider: "github-models"), outdir) }
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "leaves the failures the list expects outdir, and asks no model when every one is expected", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      expected = File.join(dir, "expected.yaml")
      File.write(expected, "- {test: zombie_handled, status: failed, reason: no init in the image}\n")
      Analyze.prepare(results, options(expected: expected), outdir).should be_true
      body = File.read(File.join(outdir, "request.json"))
      body.should_not contain("zombie_handled")
      File.read(File.join(outdir, "expected.md")).should contain("- **zombie_handled**, failed: no init in the image")

      File.write(expected, "- {test: zombie_handled, status: failed, reason: no init}\n- {test: node_drain, status: failed, reason: node-local storage}\n")
      Analyze.prepare(results, options(expected: expected), outdir).should be_false
      File.exists?(File.join(outdir, "request.json")).should be_false
      File.read(File.join(outdir, "analysis.md")).should contain("- **node_drain**, failed: node-local storage")

      Analyze.prepare(results, options(expected: expected, analyze_expected: true), outdir).should be_true
      File.read(File.join(outdir, "request.json")).should contain("zombie_handled")
      File.read(File.join(outdir, "expected.md")).should contain("analyzed too, as asked")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "cuts the facts to their limit, the cluster's state after the logs, and says what it cut", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir, events: 30)
      outdir = File.join(dir, "out")
      Analyze.prepare(results, options(max_kb: 12), outdir)
      notes = JSON.parse(File.read(File.join(outdir, "state.json")))["notes"].as_a.map(&.as_s)
      notes.any?(&.includes?("the events and the pods left out")).should be_true
      user = JSON.parse(File.read(File.join(outdir, "request.json")))["messages"][0]["content"].as_s
      user.should_not contain("FailedScheduling")
      user.should contain(%("id":"T1-R1"))
      expect_raises(Analyze::Error, /larger than 1024 bytes/) { Analyze.prepare(results, options(max_kb: 1), outdir) }
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "renders an answer with the suite's text for every fact cited, and leaves out ids that aren't facts", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      expected = File.join(dir, "expected.yaml")
      File.write(expected, "- {test: liveness, status: failed}\n")
      Analyze.prepare(results, options(expected: expected), outdir)
      answer = anthropic_answer([reading("node_drain", ["T1-C1", "T1-R1", "T9-X1"]), reading("zombie_handled", ["made up"], "medium")])
      notes = Analyze.render(outdir, reply(dir, answer), 200)
      md = File.read(File.join(outdir, "analysis.md"))
      md.should contain("### AI analysis (advisory, generated by `claude-opus-5-5`")
      md.should contain("**node_drain**, failed. *Likely cause:* the volume is tied to the drained node")
      md.should contain("scheduling_failed Pod/db-0 in cnf: 2 node(s) didn't match PersistentVolume's node affinity (T1-C1); StatefulSet/db in cnf: not Ready within 180s of eviction (T1-R1). (1 cited fact(s) not in the facts left out.)")
      md.should contain("*Confidence:* high. *Next step:* check the runner or cluster: storage that follows a pod")
      md.should contain("*Supported by:* nothing in the facts (the 1 fact(s) it cited are not in them): treat the cause as unsupported.")
      md.should contain("*Confidence:* low (no cited fact is in the facts).")
      md.should_not contain("T9-X1")
      notes.should contain("note: left out of the support for node_drain, not facts of this run: T9-X1")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "renders an OpenAI-compatible answer in a code fence or a sentence, and says which test it left out", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      Analyze.prepare(results, options(provider: "openai-compatible", model: "m", endpoint: "http://x/v1"), outdir)
      json = {"tests" => [reading("node_drain", ["T1-R1"], "insufficient_evidence")]}.to_json
      ["```json\n#{json}\n```", "Here is the analysis: #{json} I hope it helps."].each do |content|
        warnings = Analyze.render(outdir, reply(dir, {"model" => "m", "choices" => [{"message" => {"content" => content}}]}), 200)
        warnings.select(&.starts_with?("AI analysis skipped")).should be_empty
        md = File.read(File.join(outdir, "analysis.md"))
        md.should contain("**node_drain**, failed.")
        md.should contain("*Confidence:* insufficient evidence.")
        md.should contain("_No reading of `zombie_handled`: the model's answer leaves it out._")
      end
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "turns an error, a refusal, a cut answer or one that isn't the JSON into a warning, never an analysis", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      Analyze.prepare(results, options, outdir)
      cases = {
        {400, {"type" => "error", "error" => {"type" => "invalid_request_error", "message" => "model: nope"}}} => "the endpoint answered HTTP 400: model: nope",
        {200, {"stop_reason" => "refusal", "content" => [] of String}}                                         => "declined the request",
        {200, {"stop_reason" => "max_tokens", "content" => [] of String}}                                      => "cut at max_tokens",
        {200, {"stop_reason" => "end_turn", "content" => [{"type" => "text", "text" => "not json"}]}}          => "not the expected JSON; it began: not json",
      }
      cases.each do |(status, body), message|
        warnings = Analyze.render(outdir, reply(dir, body), status)
        warnings.any?(&.includes?(message)).should be_true
        File.exists?(File.join(outdir, "analysis.md")).should be_false
      end
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "writes the model's text as plain text", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      Analyze.prepare(results, options, outdir)
      bad = reading("node_drain", ["T1-R1"]).merge({"likely_cause" => "<img src=x> ![t](http://e/x.png) [l](http://e) | cell"})
      Analyze.render(outdir, reply(dir, anthropic_answer([bad])), 200)
      File.read(File.join(outdir, "analysis.md")).should contain("&lt;img src=x&gt; !\\[t\\](http\\://e/x.png) \\[l\\](http\\://e) \\| cell")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "prepares and renders from the command line, and refuses what it can't use", tags: ["points"] do
    dir = File.tempname("analyze")
    begin
      results = analyze_run(dir)
      outdir = File.join(dir, "out")
      prepared = ShellCmd.run_testsuite("analyze prepare --results-file #{results} --model claude-opus-5-5 --dir #{outdir}")
      prepared[:status].success?.should be_true
      prepared[:output].should contain("Request: #{outdir}/request.json")
      response = reply(dir, anthropic_answer([reading("node_drain", ["T1-R1"]), reading("zombie_handled", ["T2-R1"])]))
      rendered = ShellCmd.run_testsuite("analyze render --dir #{outdir} --response #{response} --http-status 200")
      rendered[:status].success?.should be_true
      rendered[:output].should contain("Analysis: #{outdir}/analysis.md")

      ShellCmd.run_testsuite("analyze prepare --results-file #{results} --dir #{outdir}")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      ShellCmd.run_testsuite("analyze prepare --results-file #{results} --model m")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      ShellCmd.run_testsuite("analyze prepare --results-file #{results} --model m --include all --dir #{outdir}")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      ShellCmd.run_testsuite("analyze prepare --results-file #{results} --model m --provider openai-compatible --dir #{outdir}")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      ShellCmd.run_testsuite("analyze render --dir #{dir}/nothing --response #{response} --http-status 200")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      ShellCmd.run_testsuite("analyze --dir #{outdir}")[:status].exit_code.should eq(USAGE_EXIT_CODE)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end
end
