require "../spec_helper"
require "json"
require "../../src/tasks/mcp/server"

# Drives `cnti-testsuite mcp` over stdio and asserts the transport contract:
# every line written to stdout is a valid JSON-RPC 2.0 message (a single stray
# non-protocol line would corrupt the session), and the tools keep concurrent
# runs and CNF install/uninstall behind the gates the server declares.
# Needs no cluster.
private def mcp_exchange(requests : Array(String), args = [] of String) : Array(JSON::Any)
  process = Process.new("./cnti-testsuite", ["mcp"] + args,
    input: Process::Redirect::Pipe,
    output: Process::Redirect::Pipe,
    error: Process::Redirect::Pipe)
  requests.each { |r| process.input.puts(r) }
  process.input.close
  output = process.output.gets_to_end
  process.wait
  output.split('\n').reject(&.strip.empty?).map { |line| JSON.parse(line) }
end

private def call(id : Int32, tool : String, arguments = {} of String => String) : String
  {jsonrpc: "2.0", id: id, method: "tools/call", params: {name: tool, arguments: arguments}}.to_json
end

private def by_id(messages : Array(JSON::Any)) : Hash(Int64, JSON::Any)
  messages.select { |m| m["id"]?.try(&.as_i64?) }.to_h { |m| {m["id"].as_i64, m} }
end

private def error_text(message : JSON::Any) : String
  message["result"]["isError"].as_bool.should be_true
  message["result"]["content"][0]["text"].as_s
end

describe "mcp server" do
  it "emits only valid JSON-RPC 2.0 on stdout and returns the expected shape", tags: ["points"] do
    messages = mcp_exchange([
      %({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}),
      %({"jsonrpc":"2.0","method":"notifications/initialized"}),
      %({"jsonrpc":"2.0","id":2,"method":"tools/list"}),
      call(3, "list_tests"),
    ])

    # The notification gets no reply: three requests, three messages.
    messages.size.should eq(3)
    messages.each { |m| m["jsonrpc"].as_s.should eq("2.0") }

    replies = by_id(messages)
    replies[1]["result"]["protocolVersion"].as_s.should eq("2025-06-18")

    tools = replies[2]["result"]["tools"].as_a.to_h { |t| {t["name"].as_s, t} }
    tools.keys.should eq(["list_tests", "run_test", "start_run", "get_run", "cancel_run", "get_results"])
    # Install and uninstall are hidden unless --allow-install is passed.
    tools.has_key?("cnf_install").should be_false
    ["list_tests", "get_run", "get_results"].each do |name|
      tools[name]["annotations"]["readOnlyHint"].as_bool.should be_true
    end
    # Running tests changes the cluster: no hint claims otherwise, so the MCP
    # default (destructive) applies.
    ["run_test", "start_run", "cancel_run"].each do |name|
      tools[name]["annotations"]?.should be_nil
    end
    # A run tool's outputSchema describes what its structuredContent holds.
    tools["get_run"]["outputSchema"]["required"].as_a.map(&.as_s).should contain("runId")
    tools["run_test"]["outputSchema"]["$schema"]?.should_not be_nil

    tests = replies[3]["result"]["structuredContent"]["tests"].as_a
    tests.map { |t| t["name"].as_s }.sort.should eq(CNFManager::TestRegistry.all.keys.sort)
  end

  it "answers an unsupported protocol version with its own and replies to no notification", tags: ["points"] do
    messages = mcp_exchange([
      %({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}),
      %({"jsonrpc":"2.0","method":"notifications/unknown"}),
      %({"jsonrpc":"2.0","id":2,"method":"does/not/exist"}),
    ])
    messages.size.should eq(2)
    replies = by_id(messages)
    replies[1]["result"]["protocolVersion"].as_s.should eq("2025-06-18")
    replies[2]["error"]["code"].as_i.should eq(-32601)
  end

  it "refuses what it cannot run, and hides install without --allow-install", tags: ["points"] do
    replies = by_id(mcp_exchange([
      call(1, "run_test", {"name" => "no_such_test"}),
      call(2, "start_run", {"name" => "no_such_suite"}),
      call(3, "get_run", {"runId" => "nope"}),
      call(4, "cnf_install", {"cnf_config" => "x.yml"}),
    ]))
    error_text(replies[1]).should contain("Unknown test")
    error_text(replies[2]).should contain("Unknown suite, category or test")
    error_text(replies[3]).should contain("No run")
    error_text(replies[4]).should contain("--allow-install")
  end

  it "starts a run of a suite, a category or a single test", tags: ["points"] do
    # Each in its own session, so the lock of one does not refuse the next.
    ["all", "configuration", "liveness"].each do |run_name|
      reply = by_id(mcp_exchange([call(1, "start_run", {"name" => run_name})]))[1]
      reply["result"]["structuredContent"]["status"].as_s.should eq("running")
      reply["result"]["structuredContent"]["runId"].as_s.empty?.should be_false
    end
  end

  it "sends no reply to a request the client cancelled", tags: ["points"] do
    # The server reads the cancellation before the run's process has started,
    # so the run is stopped and its request must stay unanswered.
    messages = mcp_exchange([
      call(1, "run_test", {"name" => "liveness"}),
      %({"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}),
      %({"jsonrpc":"2.0","id":2,"method":"ping"}),
    ])
    replies = by_id(messages)
    replies.has_key?(1_i64).should be_false
    replies[2]["result"].as_h.empty?.should be_true
  end

  it "keeps serving after a batch, a bare value or non-object params", tags: ["points"] do
    messages = mcp_exchange([
      %([{"jsonrpc":"2.0","id":1,"method":"ping"}]),
      %("hello"),
      %({"jsonrpc":"2.0","id":2,"method":"tools/call","params":[]}),
      %({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_run","arguments":[]}}),
      %({"jsonrpc":"2.0","id":4,"method":"ping"}),
    ])
    messages.size.should eq(5)
    messages[0]["error"]["code"].as_i.should eq(-32600)
    messages[1]["error"]["code"].as_i.should eq(-32600)
    replies = by_id(messages)
    replies[2]["error"]["code"].as_i.should eq(-32602)
    replies[3]["error"]["code"].as_i.should eq(-32602)
    replies[4]["result"].as_h.empty?.should be_true
  end

  it "refuses a second run while one is going, and frees the lock when the session ends", tags: ["points"] do
    replies = by_id(mcp_exchange([
      call(1, "start_run", {"name" => "all"}),
      call(2, "start_run", {"name" => "liveness"}),
    ]))
    first = replies[1]["result"]["structuredContent"]
    first["status"].as_s.should eq("running")
    first["runId"].as_s.empty?.should be_false
    error_text(replies[2]).should contain("already in progress")

    # Closing stdin stops the run that is still going, so the lock is free
    # again for the next session.
    second = by_id(mcp_exchange([call(1, "start_run", {"name" => "all"})]))
    second[1]["result"]["structuredContent"]["status"].as_s.should eq("running")
  end

  it "exposes cnf_install (destructive) only with --allow-install", tags: ["points"] do
    messages = mcp_exchange([%({"jsonrpc":"2.0","id":1,"method":"tools/list"})], args: ["--allow-install"])
    tools = messages.first["result"]["tools"].as_a
    install = tools.find { |t| t["name"].as_s == "cnf_install" }
    install.should_not be_nil
    install.not_nil!["annotations"]["destructiveHint"].as_bool.should be_true
  end
end
