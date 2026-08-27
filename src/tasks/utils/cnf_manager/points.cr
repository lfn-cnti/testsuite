require "totem"
require "../cli_invocation"
require "colorize"
require "../../../modules/helm"
require "uuid"

module CNFManager
  enum ResultStatus
    Passed
    Failed
    Skipped
    NA
    Error

    def to_string
      case self
      when Passed then "passed"
      when Failed then "failed"
      when Skipped then "skipped"
      when NA then "na"
      when Error then "error"
      else ""
      end
    end
  end

  class TestCaseResult
    property testcase : String
    property status : CNFManager::ResultStatus
    property result_message : String?
    property result_description : Array(String)
    property start_time : Time
    property end_time : Time
    property result_remediation : Array(String)
    property result_impacted_resources : Array(Hash(String, String))

    def initialize(@testcase : String = "",
                   @status : CNFManager::ResultStatus = CNFManager::ResultStatus::Skipped,
                   @result_message : String? = nil,
                   @result_description : Array(String) = [] of String,
                   @start_time : Time = Time.utc,
                   @end_time : Time = Time.utc,
                   @result_remediation : Array(String) = [] of String,
                   @result_impacted_resources : Array(Hash(String, String)) = [] of Hash(String, String))
    end

    # Backward-compatible constructor for old code that passes (status, message)
    def self.new(status : CNFManager::ResultStatus, message : String? = nil)
      new("", status, message)
    end

    def update(status : CNFManager::ResultStatus, message : String?)
      @status = status
      @result_message = message
    end

    def passed(message : String?)
      @status = CNFManager::ResultStatus::Passed
      @result_message = message
    end

    def failed(message : String?)
      @status = CNFManager::ResultStatus::Failed
      @result_message = message
    end

    def skipped(message : String?)
      @status = CNFManager::ResultStatus::Skipped
      @result_message = message
    end

    def na(message : String?)
      @status = CNFManager::ResultStatus::NA
      @result_message = message
    end

    def error(message : String?)
      @status = CNFManager::ResultStatus::Error
      @result_message = message
    end

    def append_description(text : String)
      @result_description << text
    end

    # Guidance on how to fix the failure (e.g. Kubescape remediation, config hints).
    def append_remediation(text : String)
      @result_remediation << text
    end

    # A resource that caused/participated in the failure. kind+name are required;
    # namespace/container/pod/reason are recorded only when provided.
    def add_impacted_resource(kind : String, name : String, namespace : String? = nil,
                              container : String? = nil, pod : String? = nil, reason : String? = nil)
      entry = {"kind" => kind, "name" => name}
      entry["namespace"] = namespace if namespace
      entry["container"] = container if container
      entry["pod"] = pod if pod
      entry["reason"] = reason if reason
      @result_impacted_resources << entry
    end

    def set_start_time()
      @start_time = Time.utc
    end

    def set_end_time()
      @end_time = Time.utc
    end

    def duration() : Time::Span
      @end_time - @start_time
    end

    def points : Int32
      CNFManager::Points.task_points(@testcase, @status) || 0
    end

    def set_testcase(testcase : String)
      @testcase = testcase
    end

    def decorated_result_message() : String
      tc_emoji = CNFManager::Points.emoji_by_task(@testcase)
      cat_emoji = CNFManager::Points.task_emoji_by_task(@testcase)
      case @status
      when CNFManager::ResultStatus::Passed
        "   #{cat_emoji}PASSED: [#{@testcase}] #{@result_message} #{tc_emoji}"
      when CNFManager::ResultStatus::Failed
        "   #{cat_emoji}FAILED: [#{@testcase}] #{@result_message} #{tc_emoji}"
      when CNFManager::ResultStatus::Skipped
        "⏭️  #{cat_emoji}SKIPPED: [#{@testcase}] #{@result_message} #{tc_emoji}"
      when CNFManager::ResultStatus::NA
        "⏭️  #{cat_emoji}N/A: [#{@testcase}] #{@result_message} #{tc_emoji}"
      when CNFManager::ResultStatus::Error
        "💥  #{cat_emoji}ERROR: [#{@testcase}] #{@result_message}"
      else
        ""
      end
    end

    def self.empty
      new
    end
  end

  module Points
    @@logger : ::Log = Log.for("Points")

    class Results
      @@file : String = ""
      @@dir : String? = nil

      @@logger : ::Log = Log.for("Points").for("Results")

      DEFAULT_DIR     = File.join(CNTI_DIR, "results")
      RESULTS_DIR_ARG = "results-dir"
      RESULTS_DIR_ENV = "CNF_TESTSUITE_RESULTS_DIR"
      LATEST_NAME     = "latest.yml"

      # Directory results are written to: `--results-dir PATH` on the command
      # line, else CNF_TESTSUITE_RESULTS_DIR, else ./cnti/results. Resolved once
      # per process and creates nothing -- delete_results reads it too.
      def self.dir : String
        @@dir ||= begin
          value = CLIInvocation.option(RESULTS_DIR_ARG) || ENV[RESULTS_DIR_ENV]?
          value.presence || DEFAULT_DIR
        end
      end

      # Stable path to the newest results file, so scripts need not sort the
      # directory: a relative symlink repointed whenever a results file is
      # created (a copy, kept current, where symlinks are unsupported).
      def self.latest : String
        File.join(dir, LATEST_NAME)
      end

      def self.file
        # (Re)create the file when it does not exist - including when something
        # external (e.g. delete_results in another process) removed it while
        # this process holds a handle to its path.
        unless self.file_exists?
          @@file = CNFManager::Points.create_final_results_yml_name
          self.create_file
          @@logger.for("file").debug { "Results file created: #{@@file}" }
        end
        @@file
      end

      def self.file_exists?
        !@@file.blank? && File.exists?(@@file)
      end

      private def self.create_file
        File.open(@@file, "w") { |f| YAML.dump(CNFManager::Points.template_results_yml, f) }
        point_latest_at(@@file)
      end

      # Repoint `latest` at `path` without a window where it is missing: link
      # under a temporary name, then rename over the old pointer. The target is
      # relative, so a results directory stays self-contained when moved.
      private def self.point_latest_at(path : String)
        tmp = "#{latest}.#{Process.pid}.tmp"
        File.delete?(tmp)
        File.symlink(File.basename(path), tmp)
        File.rename(tmp, latest)
      rescue ex : File::Error
        @@logger.for("point_latest_at").warn { "Could not symlink #{latest} -> #{path} (#{ex.message}); copying instead" }
        FileUtils.cp(path, latest)
      end

      # Where `latest` had to be a copy, bring it up to date after a write.
      def self.refresh_latest
        return unless file_exists? && File.exists?(latest) && !File.symlink?(latest)
        FileUtils.cp(@@file, latest)
      rescue ex : File::Error
        @@logger.for("refresh_latest").warn { "Could not refresh #{latest}: #{ex.message}" }
      end

      def self.ensure_results_file!
        unless File.exists?(self.file)
          raise File::NotFoundError.new("ERROR: results file not found", file: self.file)
        end
      end
    end

    # The evaluated success criterion of one task group.
    record GroupResult,
      group : String,
      scope : String,
      min_passed : Int32,
      min_ratio : Float64?,
      declared_count : Int32,
      max_failed : Int32?,
      passed_count : Int32,
      max_passed : Int32,
      failed_count : Int32,
      passed : Bool

    # Groups evaluated so far, in evaluation order. SAM runs a task's
    # dependencies before its body, so a group is always recorded after the
    # groups nested inside it: the last entry is the outermost group, and its
    # verdict is the run's.
    @@group_results = [] of GroupResult

    def self.group_results : Array(GroupResult)
      @@group_results
    end

    def self.clear_group_results
      @@group_results.clear
    end

    def self.group_criteria(group : String) : CNFManager::GroupCriterion?
      CNFManager::GroupRegistry.criterion_for(group)
    end

    # Evaluates `group` against its criterion and records the verdict. Called by
    # each group's task once its members have run.
    def self.evaluate_group!(group : String) : GroupResult?
      criteria = group_criteria(group)
      return nil if criteria.nil?

      scope = criteria.scope || group
      min_passed = criteria.min_passed
      max_failed = criteria.max_failed

      if scope == CNFManager::EVERY_TEST
        passed_count = total_passed([] of String)
        max_passed = total_max_passed([] of String)
        failed_count = failed_count_for(nil)
      else
        passed_count = total_passed(scope)
        max_passed = total_max_passed(scope)
        failed_count = failed_count_for(scope)
      end

      # The ratio is taken against the tests that exist in scope, not the ones
      # this run reached: max_passed shrinks when tests are excluded, and cert
      # takes an `exclude` argument, so a ratio over it could be satisfied by
      # running fewer tests.
      declared_count = scope == CNFManager::EVERY_TEST ? all_task_test_names.size : tasks_by_tag(scope).size
      ratio = criteria.min_ratio

      passed = passed_count >= min_passed
      if ratio
        # An empty scope would make the ratio vacuously true - the same trap as
        # a criterion scoped to a tag no test carries - so fail instead.
        passed = passed && declared_count > 0 && (passed_count.to_f / declared_count) >= ratio
      end
      passed = passed && failed_count <= max_failed if max_failed

      result = GroupResult.new(group: group, scope: scope, min_passed: min_passed,
                               min_ratio: ratio, declared_count: declared_count,
                               max_failed: max_failed, passed_count: passed_count,
                               max_passed: max_passed, failed_count: failed_count,
                               passed: passed)
      @@group_results.reject! { |existing| existing.group == group }
      @@group_results << result
      result
    end

    # Number of recorded items that failed. With a scope, only the tests carrying
    # that tag count; with nil, every recorded item does.
    def self.failed_count_for(scope : String?) : Int32
      scoped = scope ? tasks_by_tag(scope) : nil
      return 0 if scoped && scoped.empty?

      yaml = File.open("#{Results.file}") { |file| YAML.parse(file) }
      items = yaml["items"]?.try(&.as_a?) || [] of YAML::Any
      items.count do |item|
        name = item["name"]?.try(&.as_s?)
        next false unless name
        next false if scoped && !scoped.includes?(name)
        item["status"]?.try(&.as_s?) == "failed"
      end
    end

    def self.create_final_results_yml_name
      dir = Results.dir
      begin
        FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
      rescue File::AccessDeniedError
        stdout_failure("ERROR: missing write permission for results directory #{dir}")
        @@logger.for("create_final_results_yml_name").error { "Could not create #{dir} directory, access denied" }
        exit 1
      end
      File.join(dir, "cnf-testsuite-results-" + Time.local.to_s("%Y%m%d-%H%M%S-%L") + ".yml")
    end

    # Version of the results-file schema. Bump when the file's structure changes
    # so automation can detect the contract it is reading.
    RESULTS_SCHEMA_VERSION = 1

    def self.clean_results_yml
      if File.exists?("#{Results.file}")
        results = File.open("#{Results.file}") { |f| YAML.parse(f) }
        File.open("#{Results.file}", "w") do |f|
          # With no items left, the derived verdict is passed/0; carrying the
          # previous status/exit_code over would contradict the (empty) items.
          YAML.dump({name:              results["name"],
                     testsuite_version: ReleaseManager::VERSION,
                     schema_version:    RESULTS_SCHEMA_VERSION,
                     status:            "passed",
                     exit_code:         0,
                     items:             [] of YAML::Any},
            f)
        end
      end
    end

    private def self.dynamic_task_points(task, status_name) : Int32?
      metadata = CNFManager::TestRegistry[task]?
      unless metadata
        # Every test declares its own scoring at its definition, so a miss means
        # the task was never declared with scored_task. Surface it rather than
        # silently scoring it.
        @@logger.for("dynamic_task_points").warn { "Task: #{task} is not a declared test" }
        stdout_warning "Test '#{task}' is not declared with scored_task, scoring it as a normal test."
        return case status_name
               when "pass" then CNFManager::TestType::Normal.pass_points
               when "fail" then CNFManager::TestType::Normal.fail_points
               else             0
               end
      end

      metadata.points(status_name)
    end

    # Returns what the potential points should be (for a points type) in order to assign those points to a task
    def self.task_points(task, status : CNFManager::ResultStatus = CNFManager::ResultStatus::Passed)
      case status
      when CNFManager::ResultStatus::Passed
        resp = dynamic_task_points(task, "pass")
      when CNFManager::ResultStatus::Failed
        resp = dynamic_task_points(task, "fail")
      when CNFManager::ResultStatus::Skipped
        resp = dynamic_task_points(task, "skipped")
      when CNFManager::ResultStatus::NA
        resp = dynamic_task_points(task, "na")
      when CNFManager::ResultStatus::Error
        resp = 0
      else
        resp = dynamic_task_points(task, status.to_s.downcase)
      end
      @@logger.for("task_points").info { "Task: #{task} is worth: #{resp} points" }
      resp
    end

    def self.tasks_by_tag_intersection(tags)
      tasks = tags.reduce([] of String) do |acc, t|
        if acc.empty?
          acc = tasks_by_tag(t)
        else
          acc = acc & tasks_by_tag(t)
        end
      end
    end

    # Gets the total assigned points for a tag (or all total points) from the results file.
    # Usesful for calculation categories total.
    def self.total_points(tag = nil) : Int32
      total_tasks_points([tag])[0]
    end

    def self.total_points(tags : Array(String) = [] of String) : Int32
      total_tasks_points(tags)[0]
    end

    def self.total_passed(tag = nil) : Int32
      total_tasks_points([tag])[1]
    end

    def self.total_passed(tags : Array(String) = [] of String) : Int32
      total_tasks_points(tags)[1]
    end

    private def self.total_tasks_points(tags : Array(String) = [] of String) : Tuple(Int32, Int32)
      logger = @@logger.for("total_tasks_points")
      if !tags.empty?
        tasks = tasks_by_tag_intersection(tags)
      else
        tasks = all_task_test_names
      end

      yaml = File.open("#{Results.file}") { |file| YAML.parse(file) }
      logger.debug { "Found tasks: #{tasks} for tags: #{tags}" }

      total_passed = 0
      total_points = 0
      yaml["items"].as_a.map do |elem|
        if elem["points"].as_i? && elem["name"].as_s? && tasks.find { |x| x == elem["name"] }
          total_points += elem["points"].as_i
          if elem["points"].as_i > 0
            total_passed += 1
          end
        end
      end
      logger.info { "Total points scored: #{total_points}, total tasks passed: #{total_passed} for tags: #{tags}" }

      {total_points, total_passed}
    end

    private def self.na_assigned?(task : String) : YAML::Any?
      yaml = File.open("#{Results.file}") { |file| YAML.parse(file) }
      assigned = yaml["items"].as_a.find do |i|
        if i["name"].as_s? && i["name"].as_s == task && i["status"].as_s? && i["status"] == "na"
          true
        end
      end
      @@logger.for("na_assigned?").debug { "NA status assigned for task: #{task}" }
      assigned
    end

    # Calculates the total potential points.
    def self.total_max_points(tag = nil) : Int32
      total_max_tasks_points([tag])[0]
    end

    def self.total_max_points(tags : Array(String) = [] of String) : Int32
      total_max_tasks_points(tags)[0]
    end

    def self.total_max_passed(tag = nil) : Int32
      total_max_tasks_points([tag])[1]
    end

    def self.total_max_passed(tags : Array(String) = [] of String) : Int32
      total_max_tasks_points(tags)[1]
    end

    # Calculates the total potential points.
    private def self.total_max_tasks_points(tags : Array(String) = [] of String) : Tuple(Int32, Int32)
      if !tags.empty?
        tasks = tasks_by_tag_intersection(tags)
      else
        tasks = all_task_test_names
      end
      max_tasks_points_over(tasks)
    end

    # Maximum achievable points/passed over an explicit set of task names,
    # excluding N/A tasks and bonus tasks that did not pass (#1465).
    private def self.max_tasks_points_over(tasks : Array(String)) : Tuple(Int32, Int32)
      logger = @@logger.for("max_tasks_points_over")
      yaml = File.open("#{Results.file}") { |file| YAML.parse(file) }
      skipped_tests = yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        test_info["status"] == "skipped" ? acc + [test_info["name"].as_s] : acc
      end
      failed_tests = yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        test_info["status"] == "failed" ? acc + [test_info["name"].as_s] : acc
      end
      bonus_tasks = tasks_by_tag("bonus")

      max_points = 0
      max_passed = 0
      tasks.each do |x|
        if na_assigned?(x)
          next
        elsif bonus_tasks.includes?(x) && (failed_tests.includes?(x) || skipped_tests.includes?(x))
          # Don't count failed tests that are bonus tests #1465.
          next
        else
          points = task_points(x)
          if points
            max_points += points
            max_passed += 1
          end
        end
      end
      logger.info { "Max points scored: #{max_points}, max tasks passed: #{max_passed}" }

      {max_points, max_passed}
    end

    def self.upsert_task(result : CNFManager::TestCaseResult)
      logger = @@logger.for("upsert_task-#{result.testcase}")

      # Raise exception when results file does not exists.
      CNFManager::Points::Results.ensure_results_file!

      results = File.open("#{Results.file}") { |f| YAML.parse(f) }
      result_items = results["items"].as_a
      # remove the existing entry
      result_items = result_items.reject { |x| x["name"] == result.testcase }

      points = result.points

      # The task result info has to be appeneded to an array of YAML::Any
      # So encode it into YAML and parse it back again to assign it.
      #
      # Only add task timestamps if the env var is set.
      task_result_info = {
        name:         result.testcase,
        status:       result.status.to_string,
        message:      result.result_message,
        type:         task_type_by_task(result.testcase),
        points:       points,
        start_time:   result.start_time.to_rfc3339(fraction_digits: 9),
        end_time:     result.end_time.to_rfc3339(fraction_digits: 9),
        task_runtime: result.duration.total_seconds,
      }
      item_node = YAML.parse(task_result_info.to_yaml).as_h
      # Optional detail buckets are only recorded when non-empty, to keep the file lean.
      unless result.result_description.empty?
        item_node[YAML::Any.new("details")] = YAML.parse(result.result_description.to_yaml)
      end
      unless result.result_remediation.empty?
        item_node[YAML::Any.new("remediation")] = YAML.parse(result.result_remediation.to_yaml)
      end
      unless result.result_impacted_resources.empty?
        item_node[YAML::Any.new("impacted_resources")] = YAML.parse(result.result_impacted_resources.to_yaml)
      end
      result_items << YAML::Any.new(item_node)

      File.open("#{Results.file}", "w") do |f|
        YAML.dump({name:              results["name"],
                   testsuite_version: ReleaseManager::VERSION,
                   schema_version:    RESULTS_SCHEMA_VERSION,
                   status:            results["status"],
                   command:           "#{Process.executable_path} #{ARGV.join(" ")}",
                   exit_code:         results["exit_code"],
                   items:             result_items}, f)
      end
      write_summary!
      logger.debug { "Task start time: #{result.start_time}, end time: #{result.end_time}" }
      logger.info { "Test case: '#{result.testcase}' has status: '#{result.status}' and is awarded: #{points} points." +
                    "Runtime: #{result.duration}" }
    end

    # Recompute the `summary` block from the current results file. The summary is
    # the single home for every aggregate number (status counts + score); there are
    # no root-level duplicates. Counts come from each item's status; the score and
    # passed/essential tallies are computed over whatever tasks have run so far, so
    # the numbers match what is reported on stdout. Preserves all other keys.
    def self.write_summary!
      results = File.open("#{Results.file}") { |f| YAML.parse(f) }
      items = results["items"]?.try(&.as_a) || [] of YAML::Any
      essential_tasks = tasks_by_tag("essential")

      passed = failed = skipped = na = error = 0
      points = 0
      essential_passed = 0
      present_tasks = [] of String
      items.each do |item|
        name = item["name"]?.try(&.as_s?) || ""
        present_tasks << name
        points += item["points"]?.try(&.as_i?) || 0
        status = item["status"]?.try(&.as_s?)
        case status
        when "passed"  then passed  += 1
        when "failed"  then failed  += 1
        when "skipped" then skipped += 1
        when "na"      then na      += 1
        when "error"   then error   += 1
        end
        essential_passed += 1 if status == "passed" && essential_tasks.includes?(name)
      end

      # Denominators are scoped to the tasks that actually ran (present items).
      max_points, max_passed = max_tasks_points_over(present_tasks)
      _, essential_max_passed = max_tasks_points_over(present_tasks & essential_tasks)

      summary = {
        total:                items.size,
        passed:               passed,
        failed:               failed,
        skipped:              skipped,
        na:                   na,
        error:                error,
        max_passed:           max_passed,
        essential_passed:     essential_passed,
        essential_max_passed: essential_max_passed,
        points:               points,
        maximum_points:       max_points,
      }

      # Derive the exit code purely from the run's outcomes, so it stays an exact
      # function of the recorded items: it drops back to 0 when the items are
      # cleaned, and cannot be clobbered by a later aggregate.
      #
      # An errored test always wins with 2 - that means the suite itself broke,
      # which is never an acceptable result. Otherwise the exit code answers
      # "did this run meet its objective?":
      #
      #   * A task group with a pass criterion (cert) is judged by that criterion
      #     alone. Individual test failures are inputs to the verdict, not a
      #     separate failure mode - the threshold already accounts for them - so
      #     `cnf-testsuite cert` exits 0 exactly when the CNF is certified.
      #   * Without a criterion (all/workload/platform) the objective is simply
      #     that nothing failed (issue #2411 - failures previously only mapped to
      #     exit 1 via the unused `required:` points.yml field, so failing runs
      #     exited 0).
      exit_code =
        if error > 0
          2
        elsif outermost = @@group_results.last?
          outermost.passed ? 0 : 1
        else
          failed > 0 ? 1 : 0
        end

      # Top-level `status` is the overall run verdict, derived from the exit code:
      # 0 -> passed, 2 -> error (critical), anything else (1) -> failed.
      run_status = exit_code == 0 ? "passed" : (exit_code == 2 ? "error" : "failed")

      summary_yaml = YAML.parse(summary.to_yaml)
      unless @@group_results.empty?
        criteria = @@group_results.map do |result|
          {group:          result.group,
           scope:          result.scope,
           min_passed:     result.min_passed,
           min_ratio:      result.min_ratio,
           declared_count: result.declared_count,
           max_failed:     result.max_failed,
           passed_count:   result.passed_count,
           max_passed:     result.max_passed,
           failed_count:   result.failed_count,
           passed:         result.passed}
        end
        summary_yaml.as_h[YAML::Any.new("criteria")] = YAML.parse(criteria.to_yaml)
      end

      merged = results.as_h
      merged[YAML::Any.new("exit_code")] = YAML::Any.new(exit_code.to_i64)
      merged[YAML::Any.new("status")] = YAML::Any.new(run_status)
      merged[YAML::Any.new("summary")] = summary_yaml
      File.open("#{Results.file}", "w") { |f| YAML.dump(merged, f) }
      Results.refresh_latest
    end

    def self.failed_required_tasks
      yaml = File.open("#{Results.file}") { |file| YAML.parse(file) }
      yaml["items"].as_a.reduce([] of String) do |acc, i|
        if i["status"].as_s == "failed" && i["name"].as_s? && task_required(i["name"].as_s)
          (acc << i["name"].as_s)
        else
          acc
        end
      end
    end

    private def self.task_required(task)
      # No test has ever declared itself required; exit codes come from the
      # group criteria now. Kept so failed_required_tasks still compiles.
      false
    end

    def self.all_task_test_names
      # Platform tests are excluded, as they always were: this feeds the
      # denominators for a workload run.
      CNFManager::TestRegistry.all.reject { |_, metadata| metadata.scope.platform? }.keys
    end

    def self.tasks_by_tag(tag)
      result_items = CNFManager::TestRegistry.by_tag(tag)
      @@logger.for("tasks_by_tag").debug { "Found tasks: #{result_items} for tag: #{tag}" }

      result_items
    end

    def self.emoji_by_task(task)
      CNFManager::TestRegistry[task]?.try(&.emoji) || ""
    end

    def self.tags_by_task(task) : Array(String)
      CNFManager::TestRegistry.tags_for(task)
    end

    private def self.task_type_by_task(task)
      CNFManager::TestRegistry[task]?.try(&.type.to_tag) || ""
    end

    def self.task_emoji_by_task(task)
      case self.task_type_by_task(task)
      when "essential"
        "🏆"
      when "bonus"
        "✨"
      else
        ""
      end
    end

    def self.template_results_yml
      # TODO add tags for category summaries
      YAML.parse <<-END
name: cnf testsuite
testsuite_version: <%= CnfTestSuite::VERSION %>
schema_version: #{RESULTS_SCHEMA_VERSION}
status:
exit_code: 0
items: []
END
    end
  end
end
