require "json"
require "yaml"

module MCP
  # One run of a test/suite/lifecycle command as a child process invoked with
  # `--output json`. stdout is the results document; stderr is the human/progress
  # trail, which becomes MCP progress notifications while the request that
  # started the run is still open, and the run's progress for get_run.
  class Run
    getter id : String
    @status : String = "running"
    @progress : Int32 = 0
    @message : String? = nil

    def initialize(@id : String, @task : String, @extra_args : Array(String), @log : ::Log)
      @process = nil.as(Process?)
      @results_json = nil.as(String?)
      @exit_code = nil.as(Int32?)
      @error_message = nil.as(String?)
      @cancelled = false
      @done = Channel(Nil).new(1)
      @progress_token = nil.as(JSON::Any?)
      @notify = nil.as(Proc(String, String, Nil)?)
      @stderr_tail = Deque(String).new
    end

    # How many of the child's last stderr lines a failed run reports: enough for
    # the suite's own reason ("You must install a CNF first."), not its whole log.
    STDERR_TAIL = 5

    # Progress notifications go out only while the request is open: a sync run
    # sets this for its whole life, an async run never does (it has already been
    # answered, so its progress is read through get_run instead).
    def notify_progress(token : JSON::Any, &block : String, String ->)
      @progress_token = token
      @notify = block
    end

    def finished? : Bool
      @status != "running"
    end

    # Re-invoke this binary for the task, stream stderr as progress, capture the
    # stdout JSON document. Blocks the calling fiber until the child exits. The
    # child is started without a shell, so its arguments are never interpreted
    # and terminate signals the suite itself rather than a wrapper.
    def execute
      bin = Process.executable_path || "cnti-testsuite"
      args = [@task, "--output", "json"] + @extra_args
      @log.info { "run #{@id}: #{bin} #{args.join(" ")}" }

      process = Process.new(bin, args,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe)
      @process = process
      # A cancel that arrived before the child existed had nothing to signal.
      process.terminate if @cancelled

      drained = Channel(Nil).new
      spawn do
        begin
          while eline = process.error.gets
            @log.debug { "run #{@id} stderr: #{eline}" }
            remember(eline)
            record_progress(eline.strip) if progress_line?(eline)
          end
        rescue IO::Error
        ensure
          drained.send(nil)
        end
      end

      document = process.output.gets_to_end
      result = process.wait
      drained.receive

      # A child stopped by a signal (cancel) has no exit code.
      @exit_code = result.normal_exit? ? result.exit_code : nil
      @results_json = compact_document(document)
      @status =
        if @cancelled
          "cancelled"
        else
          case @exit_code
          when 0 then "passed"
          when 1 then "failed"
          else        "error"
          end
        end
    rescue ex
      @status = "error"
      @error_message = ex.message
      @log.error(exception: ex) { "run #{@id} failed to execute" }
    ensure
      @process = nil
      @done.send(nil)
    end

    # Ask the child to stop, together with what it started (a helm install or
    # kubectl the suite is running at that moment); the run reports `cancelled`
    # once the suite has exited. The tree is read before anything is signalled:
    # once the suite is gone its children are re-parented and cannot be found.
    def cancel
      return if finished?
      @cancelled = true
      process = @process
      return unless process
      descendants(process.pid).reverse_each do |pid|
        Process.signal(Signal::TERM, pid) rescue nil
      end
      process.terminate rescue nil
    end

    # Every process under `pid`, parents before children, through `pgrep -P`.
    # Without pgrep only the suite itself is signalled.
    private def descendants(pid : Int64) : Array(Int64)
      found = [] of Int64
      queue = [pid]
      while parent = queue.shift?
        output = IO::Memory.new
        status = Process.run("pgrep", ["-P", parent.to_s], output: output, error: Process::Redirect::Close) rescue nil
        next unless status
        output.to_s.split.each do |child|
          if (c = child.to_i64?)
            found << c
            queue << c
          end
        end
      end
      found
    rescue ex
      @log.warn { "run #{@id}: could not list the processes it started (#{ex.message}); signalling the suite only" }
      [] of Int64
    end

    def wait
      return if finished?
      @done.receive
      @done.send(nil)
    end

    # The child prints one compact JSON document; re-serialize it so a document
    # that is not JSON, or spans lines, cannot break the one-message-per-line
    # framing of the server's stdout.
    private def compact_document(document : String) : String?
      return nil if document.blank?
      JSON.parse(document).to_json
    rescue JSON::ParseException
      @error_message = "the run did not print a results document"
      nil
    end

    private def remember(line : String)
      return if line.blank?
      @stderr_tail << line.strip
      @stderr_tail.shift if @stderr_tail.size > STDERR_TAIL
    end

    # The suite's own start and verdict lines (CNFManager::Points), e.g.
    # "🎬 Testing: [liveness]" and "   ✨FAILED: [immutable_configmap] ...".
    PROGRESS_LINE = /(?:Testing|PASSED|FAILED|SKIPPED|N\/A|ERROR): \[/

    private def progress_line?(line : String) : Bool
      PROGRESS_LINE.matches?(line)
    end

    private def record_progress(line : String)
      @progress += 1
      @message = line
      token = @progress_token
      notify = @notify
      return unless token && notify
      params = JSON.build do |j|
        j.object do
          j.field("progressToken") { token.to_json(j) }
          j.field "progress", @progress
          j.field "message", line
        end
      end
      notify.call("notifications/progress", params)
    end

    # The results document, or nil when the run produced none.
    def results_json : String?
      @results_json
    end

    # The failure text for a run that produced no results document.
    def failure_message : String
      message = @error_message || "the run ended with status #{@status} (exit code #{@exit_code.inspect}) without a results document"
      @stderr_tail.empty? ? message : "#{message}:\n#{@stderr_tail.join("\n")}"
    end

    # get_run / cancel_run / the immediate reply of an async run: the run's state,
    # with the results document once the run has one. Matches RUN_SCHEMA.
    def status_json : String
      JSON.build do |j|
        j.object do
          j.field "runId", @id
          j.field "status", @status
          j.field "progress", @progress
          if msg = @message
            j.field "message", msg
          end
          if code = @exit_code
            j.field "exitCode", code
          end
          # cnf_install/cnf_uninstall print no results document when they pass;
          # only a run that did not pass explains itself.
          if finished? && @status != "passed" && @results_json.nil?
            j.field "error", failure_message
          end
          if doc = @results_json
            j.field("results") { j.raw doc }
          end
        end
      end
    end
  end

  module Tools
    SUITE_AGGREGATES = ["all", "workload", "cert"]

    def self.valid_suite?(suite : String) : Bool
      SUITE_AGGREGATES.includes?(suite) ||
        CNFManager::TestRegistry.category_of.values.uniq.includes?(suite)
    end

    # {tests:[{name, category, type, scope}, ...]} for every registered test.
    def self.list_tests_json : String
      categories = CNFManager::TestRegistry.category_of
      JSON.build do |j|
        j.object do
          j.field "tests" do
            j.array do
              CNFManager::TestRegistry.all.each do |name, md|
                j.object do
                  j.field "name", name
                  j.field "category", categories[name]?
                  j.field "type", md.type.to_tag
                  j.field "scope", md.scope.to_tag
                end
              end
            end
          end
        end
      end
    end

    # get_results: the newest results document, or nil when none exists yet.
    def self.read_results_json : String?
      latest = CNFManager::Points::Results.latest
      return nil unless File.exists?(latest)
      YAML.parse(File.read(latest)).to_json
    end

    NO_ARGS = %({"type":"object","properties":{},"additionalProperties":false})

    # The structuredContent of get_run, cancel_run and the async run tools: the
    # run's state, with the results document (RESULTS_SCHEMA) once there is one.
    RUN_SCHEMA = %({"type":"object","properties":{) +
                 %("runId":{"type":"string"},) +
                 %("status":{"type":"string","enum":["running","passed","failed","error","cancelled"]},) +
                 %("progress":{"type":"integer","description":"progress lines seen so far"},) +
                 %("message":{"type":"string","description":"the latest progress line"},) +
                 %("exitCode":{"type":"integer"},) +
                 %("error":{"type":"string"},) +
                 %("results":) + MCP::RESULTS_SCHEMA +
                 %(},"required":["runId","status","progress"]})

    # The tools/list payload. cnf_install/cnf_uninstall appear only when the
    # server was started with --allow-install. Only the tools that read are
    # annotated read-only. The others leave destructiveHint out, so it takes the
    # MCP default (true): running tests against a live CNF changes the cluster
    # (they kill containers, change images, scale workloads, inject faults and
    # install tools), and the suite has no classification that could say which
    # ones do not.
    def self.list_json(allow_install : Bool) : String
      JSON.build do |j|
        j.object do
          j.field "tools" do
            j.array do
              tool(j, "list_tests",
                "List every test with its category and essential/normal/bonus type.",
                NO_ARGS, read_only: true)

              tool(j, "run_test",
                "Run a single test against the installed CNF, as `cnti-testsuite <test>` does, and return its results document when it finishes. Tests act on the cluster. Send a progressToken to receive progress notifications. A test that can take longer than the client's tool-call timeout (most chaos tests, with the TypeScript SDK's 60 s default) is better started with start_run.",
                %({"type":"object","properties":{"name":{"type":"string","description":"test name, as listed by list_tests"}},"required":["name"],"additionalProperties":false}),
                output_schema: MCP::RESULTS_SCHEMA)

              tool(j, "start_run",
                "Start a run of a suite, a category or a single test, as `cnti-testsuite <name>` does. Tests act on the cluster. Returns a runId at once; poll get_run for progress and the results document, and stop it with cancel_run. Use it for anything that can outlast a tool call.",
                %({"type":"object","properties":{"name":{"type":"string","description":"all, workload, cert, a category, or a test name as listed by list_tests"}},"required":["name"],"additionalProperties":false}),
                output_schema: RUN_SCHEMA)

              tool(j, "get_run",
                "Report the state and progress of a run started by start_run, cnf_install or cnf_uninstall, with the results document once complete.",
                %({"type":"object","properties":{"runId":{"type":"string"}},"required":["runId"],"additionalProperties":false}),
                read_only: true, output_schema: RUN_SCHEMA)

              tool(j, "cancel_run",
                "Stop a run started by start_run, cnf_install or cnf_uninstall, together with the processes it started. The run reports status cancelled once it has exited.",
                %({"type":"object","properties":{"runId":{"type":"string"}},"required":["runId"],"additionalProperties":false}),
                output_schema: RUN_SCHEMA)

              tool(j, "get_results",
                "Return the newest results document from the workspace.",
                NO_ARGS, read_only: true, output_schema: MCP::RESULTS_SCHEMA)

              if allow_install
                tool(j, "cnf_install",
                  "Install a CNF into the cluster from a cnti-testsuite.yaml. Returns a runId; poll get_run.",
                  %({"type":"object","properties":{"cnf_config":{"type":"string","description":"path to a cnti-testsuite.yaml or its directory, relative to the server's working directory"}},"required":["cnf_config"],"additionalProperties":false}),
                  destructive: true, output_schema: RUN_SCHEMA)

                tool(j, "cnf_uninstall",
                  "Uninstall the CNF currently installed in the workspace. Returns a runId; poll get_run.",
                  NO_ARGS, destructive: true, output_schema: RUN_SCHEMA)
              end
            end
          end
        end
      end
    end

    # An annotation is written only when it says something: readOnlyHint for
    # the tools that only read, destructiveHint where it is stated on purpose.
    # A hint left out takes the MCP default.
    private def self.tool(j : JSON::Builder, name : String, description : String,
                          input_schema : String, read_only : Bool = false,
                          destructive : Bool? = nil, output_schema : String? = nil)
      j.object do
        j.field "name", name
        j.field "description", description
        j.field("inputSchema") { j.raw input_schema }
        if os = output_schema
          j.field("outputSchema") { j.raw os }
        end
        if read_only || !destructive.nil?
          j.field "annotations" do
            j.object do
              j.field "readOnlyHint", true if read_only
              j.field "destructiveHint", destructive unless destructive.nil?
            end
          end
        end
      end
    end
  end
end
