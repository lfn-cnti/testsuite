require "totem"
require "colorize"
require "helm"
require "uuid"

module CNFManager
  enum ResultStatus
    Passed
    Failed
    Skipped
    NA
    Neutral
    Pass5
    Pass3
    Error

    def to_basic
      case self
      when Pass5, Pass3
        ret = CNFManager::ResultStatus::Passed
      when Neutral
        ret = CNFManager::ResultStatus::Failed
      else
        ret = self
      end
    end
  end

  struct TestCaseResult
    property state, result_message

    def initialize(@state : CNFManager::ResultStatus, @result_message : String? = nil)
    end
  end

  module Points
    @@logger : ::Log = Log.for("Points")

    class Results
      @@file : String = ""
      # @@file_used variable is needed to avoid recreation of the file
      @@file_used : Bool = false

      @@logger : ::Log = Log.for("Points").for("Results")

      def self.file
        unless @@file_used || self.file_exists?
          @@file = CNFManager::Points.create_final_results_yml_name
          self.create_file
          @@logger.for("file").debug { "Results file created: #{@@file}" }
        end
        @@file_used = true
        @@file
      end

      def self.file_exists?
        !@@file.blank? && File.exists?(@@file)
      end

      private def self.create_file
        File.open(@@file, "w") { |f| YAML.dump(CNFManager::Points.template_results_yml, f) }
      end

      def self.ensure_results_file!
        unless File.exists?(self.file)
          raise File::NotFoundError.new("ERROR: results file not found", file: self.file)
        end
      end
    end

    def self.points_yml
      points = File.open("points.yml") { |f| YAML.parse(f) }
      points.as_a
    end

    def self.create_points_yml
      EmbeddedFileManager.points_yml_write_file
    end

    def self.create_final_results_yml_name
      begin
        FileUtils.mkdir_p("results") unless Dir.exists?("results")
      rescue File::AccessDeniedError
        stdout_failure("ERROR: missing write permission in current directory")
        @@logger.for("create_final_results_yml_name").error { "Could not create ./results directory, access denied" }
        exit 1
      end
      "results/cnf-testsuite-results-" + Time.local.to_s("%Y%m%d-%H%M%S-%L") + ".yml"
    end

    def self.clean_results_yml
      if File.exists?("#{Results.file}")
        results = File.open("#{Results.file}") { |f| YAML.parse(f) }
        File.open("#{Results.file}", "w") do |f|
          YAML.dump({name:              results["name"],
                     testsuite_version: ReleaseManager::VERSION,
                     status:            results["status"],
                     exit_code:         results["exit_code"],
                     points:            results["points"],
                     items:             [] of YAML::Any},
            f)
        end
      end
    end

    private def self.dynamic_task_points(task, status_name) : Int32?
      points = points_yml.find { |x| x["name"] == task }
      @@logger.for("dynamic_task_points").warn { "Task: #{task} not found in points.yml" } unless points

      if points && points[status_name]?
        resp = points[status_name].as_i if points
      else
        points = points_yml.find { |x| x["name"] == "default_scoring" }
        resp = points[status_name].as_i if points
      end
      resp
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
        if i["name"].as_s? && i["name"].as_s == task && i["status"].as_s? && i["status"] == NA
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
      logger = @@logger.for("total_max_tasks_points")
      if !tags.empty?
        tasks = tasks_by_tag_intersection(tags)
      else
        tasks = all_task_test_names
      end

      yaml = File.open("#{Results.file}") { |file| YAML.parse(file) }
      skipped_tests = yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        if test_info["status"] == "skipped"
          acc + [test_info["name"].as_s]
        else
          acc
        end
      end
      logger.info { "Skipped tests: #{skipped_tests}" }

      failed_tests = yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        if test_info["status"] == "failed"
          acc + [test_info["name"].as_s]
        else
          acc
        end
      end
      logger.info { "Failed tests: #{failed_tests}" }

      bonus_tasks = tasks_by_tag("bonus")
      logger.info { "Bonus tests: #{failed_tests}" }

      max_points = 0
      max_passed = 0
      tasks.each do |x|
        logger.info { sprintf("Task: %s -> failed: %s, skipped: NA: %s, bonus: %s",
          x, failed_tests.includes?(x), skipped_tests.includes?(x), na_assigned?(x), bonus_tasks.includes?(x)) }
        if na_assigned?(x)
          next
        elsif bonus_tasks.includes?(x) && (failed_tests.includes?(x) || skipped_tests.includes?(x))
          logger.debug { "Bonus tasks not counted in maximum" }
          # Don't count failed tests that are bonus tests #1465.
          next
        else
          points = task_points(x)
          if points
            max_points += points
            max_passed += 1
          else
            next
          end
        end
      end
      logger.info { "Max points scored: #{max_points}, max tasks passed: #{max_passed} for tags: #{tags}" }

      {max_points, max_passed}
    end

    def self.upsert_task(task, status, points, start_time)
      logger = @@logger.for("upsert_task-#{task}")

      # Raise exception when results file does not exists.
      CNFManager::Points::Results.ensure_results_file!

      results = File.open("#{Results.file}") { |f| YAML.parse(f) }
      result_items = results["items"].as_a
      # remove the existing entry
      result_items = result_items.reject { |x| x["name"] == task }

      end_time = Time.utc
      task_runtime = (end_time - start_time)

      # The task result info has to be appeneded to an array of YAML::Any
      # So encode it into YAML and parse it back again to assign it.
      #
      # Only add task timestamps if the env var is set.
      if ENV.has_key?("TASK_TIMESTAMPS")
        task_result_info = {
          name:         task,
          status:       status,
          type:         task_type_by_task(task),
          points:       points,
          start_time:   start_time,
          end_time:     end_time,
          task_runtime: "#{task_runtime}",
        }
        result_items << YAML.parse(task_result_info.to_yaml)
      else
        task_result_info = {
          name:   task,
          status: status,
          type:   task_type_by_task(task),
          points: points,
        }
        result_items << YAML.parse(task_result_info.to_yaml)
      end

      File.open("#{Results.file}", "w") do |f|
        YAML.dump({name:              results["name"],
                   testsuite_version: ReleaseManager::VERSION,
                   status:            results["status"],
                   command:           "#{Process.executable_path} #{ARGV.join(" ")}",
                   points:            results["points"],
                   exit_code:         results["exit_code"],
                   items:             result_items}, f)
      end
      logger.debug { "Task start time: #{start_time}, end time: #{end_time}" }
      logger.info { "Task: '#{task}' has status: '#{status}' and is awarded: #{points} points." +
        "Runtime: #{task_runtime}" }
    end

    def self.failed_task(task, msg)
      upsert_task(task, FAILED, task_points(task, false), start_time)
      stdout_failure "#{msg}"
    end

    def self.passed_task(task, msg)
      upsert_task(task, PASSED, task_points(task), start_time)
      stdout_success "#{msg}"
    end

    def self.skipped_task(task, msg)
      upsert_task(task, SKIPPED, task_points(task), start_time)
      stdout_success "#{msg}"
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
      points = points_yml.find { |x| x["name"] == task }
      @@logger.for("task_required").warn { "Task: '#{task}' not found in points.yml" } unless points
      if points && points["required"]? && points["required"].as_bool == true
        true
      else
        false
      end
    end

    def self.all_task_test_names
      result_items = points_yml.reduce([] of String) do |acc, x|
        if x["name"].as_s == "default_scoring" || x["tags"].as_a.find { |x| x == "platform" }
          acc
        else
          acc << x["name"].as_s
        end
      end
    end

    def self.tasks_by_tag(tag)
      result_items = points_yml.reduce([] of String) do |acc, x|
        if x["tags"].as_a?
          tag_match = x["tags"].as_a.map { |parsed_tag|
            parsed_tag if parsed_tag == tag.strip
          }.uniq.compact
          if !tag_match.empty?
            acc << x["name"].as_s
          else
            acc
          end
        else
          acc
        end
      end
      @@logger.for("tasks_by_tag").debug { "Found tasks: #{result_items} for tag: #{tag}" }

      result_items
    end

    def self.emoji_by_task(task)
      logger = @@logger.for("emoji_by_task")

      md = points_yml.find { |x| x["name"] == task }
      logger.warn { "Task: '#{task}' not found in points.yml" } unless md

      if md && md["emoji"]?
        logger.debug { "Task: '#{task}' emoji: #{md["emoji"]?}" }
        resp = md["emoji"]
      else
        resp = ""
      end
    end

    def self.tags_by_task(task)
      logger = @@logger.for("tags_by_task")

      points = points_yml.find { |x| x["name"] == task }
      logger.warn { "Task: '#{task}' not found in points.yml" } unless points

      if points && points["tags"]?
        logger.debug { "Task: '#{task}' tags: #{points["tags"]?}" }
        resp = points["tags"].as_a
      else
        resp = [] of String
      end
    end

    private def self.task_type_by_task(task)
      task_type = tags_by_task(task).reduce("") do |acc, x|
        if x == "essential"
          acc = "essential"
        elsif x == "normal" && acc != "essential"
          acc = "normal"
        elsif x == "bonus" && acc != "essential" && acc != "normal"
          acc = "bonus"
        elsif x == "cert" && acc != "bonus" && acc != "essential" && acc != "normal"
          acc = "cert"
        else
          acc
        end
      end
      @@logger.debug { "Task: '#{task}' type: #{task_type}" }

      task_type
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
status:
points:
exit_code: 0
items: []
END
    end
  end
end
