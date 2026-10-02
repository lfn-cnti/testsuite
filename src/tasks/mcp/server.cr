require "json"
require "./tools"

# A minimal MCP (Model Context Protocol) server speaking JSON-RPC 2.0 over stdio,
# newline-delimited. It is a thin transport over the existing CLI and results
# contract: run tools re-invoke this same binary with `--output json` and return
# the results document; read-only tools read the task registry and the results
# file. No new test logic lives here.
#
# stdout is the protocol: only JSON-RPC messages are written there (guarded by a
# mutex). Everything human/diagnostic goes to stderr via Log, so one stray line
# can never corrupt the session.
module MCP
  # The MCP protocol version this hand-rolled layer implements: the first one
  # with tool annotations, outputSchema and structuredContent, which it uses.
  PROTOCOL_VERSION = "2025-06-18"
  SERVER_NAME      = "cnti-testsuite"

  # The results-file JSON Schema, embedded at compile time and re-serialized
  # compact (the source is pretty-printed; newlines would break the one-message-
  # per-line stdio framing). It is the outputSchema of the tools whose
  # structuredContent is a results document.
  RESULTS_SCHEMA = JSON.parse({{ read_file("#{__DIR__}/../../../docs/cnti-testsuite-results.schema.json") }}).to_json

  class Server
    @log = ::Log.for("mcp")
    @out = Mutex.new
    # One run at a time: a run occupies the shared cnti/ workspace and cluster.
    # The flock also refuses a run while another server process holds it.
    @lock : File? = nil
    # Every run of this session, by runId.
    @runs = {} of String => MCP::Run
    # Open run_test requests, by JSON-RPC request id, so that
    # notifications/cancelled can stop the run behind them.
    @open_requests = {} of String => MCP::Run
    # Requests the client cancelled: they get no reply.
    @cancelled_requests = Set(String).new

    # `results_dir` is the server's own --results-dir, passed on to every run so
    # that the runs write where get_results reads.
    def initialize(@allow_install : Bool = false, @results_dir : String? = nil)
    end

    # Read loop: one JSON-RPC message per line. Runs execute in their own fiber
    # so the loop keeps serving get_run, cancel_run and notifications/cancelled.
    # When stdin closes, runs still going are stopped before the server exits,
    # so no child outlives the session that started it.
    def run
      @log.info { "MCP server starting (protocol #{PROTOCOL_VERSION}, allow_install=#{@allow_install})" }
      while line = STDIN.gets
        line = line.strip
        next if line.empty?
        begin
          msg = JSON.parse(line)
        rescue ex : JSON::ParseException
          write_error(nil, -32700, "Parse error: #{ex.message}")
          next
        end
        # One message that does not fit what a handler expects must not end
        # the session: answer it and keep serving.
        begin
          dispatch(msg)
        rescue ex
          @log.error(exception: ex) { "failed to handle #{line[0, 200]}" }
          write_error(request_id(msg), -32603, "Internal error: #{ex.message}")
        end
      end
      @log.info { "MCP server stdin closed; stopping runs and exiting" }
      @runs.each_value(&.cancel)
      @runs.each_value(&.wait)
      release_lock
    end

    # The id of a request, for an error reply; nil when there is none to name.
    private def request_id(msg : JSON::Any) : JSON::Any?
      msg.as_h?.try(&.["id"]?)
    end

    private def dispatch(msg : JSON::Any)
      # A batch (an array) or a bare value is not a request this server takes:
      # MCP 2025-06-18 has no JSON-RPC batching.
      unless msg.as_h?
        write_error(nil, -32600, "Invalid Request: expected a JSON-RPC object")
        return
      end
      if (params = msg["params"]?) && !params.as_h?
        write_error(request_id(msg), -32602, "Invalid params: expected an object")
        return
      end
      id = msg["id"]?
      method = msg["method"]?.try(&.as_s?)
      params = msg["params"]?

      # A notification (no id) never gets a reply, known or not.
      if id.nil?
        handle_notification(method, params)
        return
      end

      case method
      when "initialize"
        handle_initialize(id, params)
      when "ping"
        write_result(id, JSON::Any.new({} of String => JSON::Any))
      when "tools/list"
        write_raw_result(id, Tools.list_json(@allow_install))
      when "tools/call"
        handle_tool_call(id, params)
      else
        write_error(id, -32601, "Method not found: #{method}")
      end
    end

    # The server implements one protocol version. As the MCP lifecycle requires,
    # a client asking for another one is answered with the version the server
    # does implement, and decides itself whether to continue; the server never
    # claims a version it does not speak.
    private def handle_initialize(id, params)
      requested = params.try(&.dig?("protocolVersion")).try(&.as_s?)
      if requested && requested != PROTOCOL_VERSION
        @log.warn { "client requested protocol #{requested}; answering with #{PROTOCOL_VERSION}" }
      end
      result = JSON.build do |j|
        j.object do
          j.field "protocolVersion", PROTOCOL_VERSION
          j.field "capabilities" { j.object { j.field("tools") { j.object { j.field "listChanged", false } } } }
          j.field "serverInfo" do
            j.object do
              j.field "name", SERVER_NAME
              j.field "version", ReleaseManager::VERSION
            end
          end
        end
      end
      write_raw_result(id, result)
    end

    private def handle_notification(method, params)
      return unless method == "notifications/cancelled"
      request_id = params.try(&.dig?("requestId")).try { |v| v.raw.to_s }
      return unless request_id
      if run = @open_requests[request_id]?
        @log.info { "request #{request_id} cancelled; stopping run #{run.id}" }
        @cancelled_requests << request_id
        run.cancel
      end
    end

    private def handle_tool_call(id, params)
      name = params.try(&.dig?("name")).try(&.as_s?)
      args = params.try(&.dig?("arguments"))
      token = params.try(&.dig?("_meta", "progressToken"))
      if args && !args.as_h? && !args.raw.nil?
        write_error(id, -32602, "Invalid params: arguments must be an object")
        return
      end

      case name
      when "list_tests"
        write_tool_result(id, Tools.list_tests_json)
      when "get_results"
        if doc = Tools.read_results_json
          write_tool_result(id, doc)
        else
          write_tool_error(id, "No results file yet; run a test first")
        end
      when "get_run", "cancel_run"
        run_id = args.try(&.dig?("runId")).try(&.as_s?)
        run = run_id.try { |r| @runs[r]? }
        unless run
          write_tool_error(id, "No run with id #{run_id.inspect}")
          return
        end
        run.cancel if name == "cancel_run"
        write_tool_result(id, run.status_json)
      when "run_test"
        test = args.try(&.dig?("name")).try(&.as_s?)
        unless test
          write_tool_error(id, "run_test requires a 'name'")
          return
        end
        # Only registered test names reach the child.
        unless CNFManager::TestRegistry.all.has_key?(test)
          write_tool_error(id, "Unknown test: #{test}")
          return
        end
        start_sync(id, token, test, [] of String)
      when "start_run"
        run_name = args.try(&.dig?("name")).try(&.as_s?)
        unless run_name
          write_tool_error(id, "start_run requires a 'name': a suite, a category or a test")
          return
        end
        # Only a known suite, category or registered test reaches the child.
        unless Tools.valid_suite?(run_name) || CNFManager::TestRegistry.all.has_key?(run_name)
          write_tool_error(id, "Unknown suite, category or test: #{run_name}")
          return
        end
        start_async(id, run_name, [] of String)
      when "cnf_install", "cnf_uninstall"
        lifecycle = name.not_nil!
        unless @allow_install
          write_tool_error(id, "#{lifecycle} is disabled; start the server with `mcp --allow-install` to install or uninstall a CNF")
          return
        end
        if lifecycle == "cnf_install"
          cfg = args.try(&.dig?("cnf_config")).try(&.as_s?)
          unless cfg
            write_tool_error(id, "cnf_install requires a 'cnf_config' path")
            return
          end
          start_async(id, lifecycle, ["--cnf-config", cfg])
        else
          start_async(id, lifecycle, [] of String)
        end
      else
        write_error(id, -32602, "Unknown tool: #{name}")
      end
    end

    # run_test: reply with the results document when the child exits; progress
    # notifications flow while the request is open. A request the client
    # cancelled gets no reply, as the MCP cancellation utility asks.
    private def start_sync(id, token, task : String, extra : Array(String))
      run = new_run(id, task, extra) || return
      request_id = id.raw.to_s
      @open_requests[request_id] = run
      if token
        run.notify_progress(token) { |method, p| write_notification(method, p) }
      end
      spawn do
        run.execute
        release_lock
        @open_requests.delete(request_id)
        next if @cancelled_requests.delete(request_id)
        if doc = run.results_json
          write_tool_result(id, doc)
        else
          write_tool_error(id, run.failure_message)
        end
      end
    end

    # start_run / cnf_install / cnf_uninstall: reply at once with the runId, so
    # a run longer than a client's tool-call timeout is followed through get_run.
    private def start_async(id, task : String, extra : Array(String))
      run = new_run(id, task, extra) || return
      write_tool_result(id, run.status_json)
      spawn do
        run.execute
        release_lock
      end
    end

    private def new_run(id, task : String, extra : Array(String)) : MCP::Run?
      unless acquire_lock
        write_tool_error(id, "A run is already in progress; only one run may use the cnti/ workspace and cluster at a time")
        return nil
      end
      if dir = @results_dir
        extra = extra + ["--results-dir", dir]
      end
      run = MCP::Run.new(Random::Secure.hex(8), task, extra, @log)
      @runs[run.id] = run
      run
    end

    private def acquire_lock : Bool
      return false if @lock
      Dir.mkdir_p(CNTI_DIR) unless Dir.exists?(CNTI_DIR)
      f = File.open(File.join(CNTI_DIR, "mcp-run.lock"), "w")
      begin
        f.flock_exclusive(blocking: false)
        @lock = f
        true
      rescue
        f.close
        false
      end
    end

    private def release_lock
      @lock.try(&.close)
      @lock = nil
    end

    # --- JSON-RPC writers (stdout is the protocol; serialize all writes) ---

    private def write_result(id, result : JSON::Any)
      write_message do |j|
        j.field "jsonrpc", "2.0"
        write_id(j, id)
        j.field "result", result
      end
    end

    private def write_raw_result(id, result_json : String)
      write_message do |j|
        j.field "jsonrpc", "2.0"
        write_id(j, id)
        j.field("result") { j.raw result_json }
      end
    end

    # A tools/call result whose structuredContent is a JSON document (string of
    # JSON), also mirrored as text content for clients that only read text.
    private def write_tool_result(id, structured_json : String)
      write_message do |j|
        j.field "jsonrpc", "2.0"
        write_id(j, id)
        j.field "result" do
          j.object do
            j.field "content" do
              j.array { j.object { j.field "type", "text"; j.field "text", structured_json } }
            end
            j.field("structuredContent") { j.raw structured_json }
          end
        end
      end
    end

    private def write_tool_error(id, message : String)
      write_message do |j|
        j.field "jsonrpc", "2.0"
        write_id(j, id)
        j.field "result" do
          j.object do
            j.field "isError", true
            j.field "content" do
              j.array { j.object { j.field "type", "text"; j.field "text", message } }
            end
          end
        end
      end
    end

    private def write_error(id, code : Int32, message : String)
      write_message do |j|
        j.field "jsonrpc", "2.0"
        write_id(j, id)
        j.field "error" { j.object { j.field "code", code; j.field "message", message } }
      end
    end

    private def write_notification(method : String, params_json : String)
      write_message do |j|
        j.field "jsonrpc", "2.0"
        j.field "method", method
        j.field("params") { j.raw params_json }
      end
    end

    private def write_id(j : JSON::Builder, id)
      if id
        j.field("id") { id.to_json(j) }
      else
        j.field "id", nil
      end
    end

    private def write_message(&)
      str = JSON.build { |j| j.object { yield j } }
      @out.synchronize do
        STDOUT.puts str
        STDOUT.flush
      end
    end
  end
end
