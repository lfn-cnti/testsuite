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

    def to_basic()
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

  struct TestcaseResult
    property state, result_message

    def initialize(@state : CNFManager::ResultStatus, @result_message : String|Nil = nil)
    end
  end

  module Points
    class Results

      enum ResultStatus
        Passed
        Failed
        Skipped
        NA
        Neutral
        Pass5
        Pass3
      end

      @@file : String = ""
      # @@file_used variable is needed to avoid recreation of the file
      @@file_used : Bool = false

      def self.file
        unless @@file_used || self.file_exists?
          @@file = CNFManager::Points.create_final_results_yml_name
          self._create_file
          Log.debug { "Results.file created: #{@@file}" }
        end
        @@file_used = true
        @@file
      end

      def self.file_exists?
        !@@file.blank? && File.exists?(@@file)
      end

      def self._create_file
        File.open(@@file, "w") do |f|
          YAML.dump(CNFManager::Points.template_results_yml, f)
        end
      end

      def self.ensure_results_file!
        unless File.exists?(self.file)
          raise File::NotFoundError.new("ERROR: results file not found", file: self.file)
        end
      end
    end

    def self.points_yml
      points = File.open("points.yml") do |f|
        YAML.parse(f)
      end
      points.as_a
    end
    
    def self.create_points_yml
      EmbeddedFileManager.points_yml_write_file
    end

    def self.create_final_results_yml_name
      begin
        FileUtils.mkdir_p("results") unless Dir.exists?("results")
      rescue File::AccessDeniedError
        Log.error {"ERROR: missing write permission in current directory"}
        exit 1
      end
      "results/cnf-testsuite-results-" + Time.local.to_s("%Y%m%d-%H%M%S-%L") + ".yml"
    end

    def self.clean_results_yml()
      if File.exists?("#{Results.file}")
        results = File.open("#{Results.file}") do |f|
          YAML.parse(f)
        end
        File.open("#{Results.file}", "w") do |f|
          YAML.dump({name: results["name"],
                     # testsuite_version: CnfTestSuite::VERSION,
                     testsuite_version: ReleaseManager::VERSION,
                     status: results["status"],
                     exit_code: results["exit_code"],
                     points: results["points"],
                     items: [] of YAML::Any}, f)
        end
      end
    end

    def self.dynamic_task_points(task, status_name)
      points =points_yml.find {|x| x["name"] == task}
      Log.warn { "****Warning**** task #{task} not found in points.yml".colorize(:yellow) } unless points
      if points && points[status_name]?
          resp = points[status_name].as_i if points
      else
        points =points_yml.find {|x| x["name"] == "default_scoring"}
        resp = points[status_name].as_i if points
      end
      resp
    end

    # Returns what the potential points should be (for a points type) in order to assign those points to a task
    def self.task_points(task, status : CNFManager::ResultStatus = CNFManager::ResultStatus::Passed)
      #todo replace case statement with dynamic point call
      case status
      when CNFManager::ResultStatus::Passed
        resp = CNFManager::Points.task_points(task, true)
      when CNFManager::ResultStatus::Failed
        resp = CNFManager::Points.task_points(task, false)
      when CNFManager::ResultStatus::Skipped
        resp = dynamic_task_points(task, "skipped")
        # field_name = "skipped"
        # points =points_yml.find {|x| x["name"] == task}
        # Log.warn { "****Warning**** task #{task} not found in points.yml".colorize(:yellow) } unless points
        # if points && points[field_name]?
        #     resp = points[field_name].as_i if points
        # else
        #   points =points_yml.find {|x| x["name"] == "default_scoring"}
        #   resp = points[field_name].as_i if points
        # end
      when CNFManager::ResultStatus::NA
        resp = dynamic_task_points(task, "na")
        # field_name = "na"
        # points =points_yml.find {|x| x["name"] == task}
        # Log.warn { "****Warning**** task #{task} not found in points.yml".colorize(:yellow) } unless points
        # if points && points[field_name]?
        #     resp = points[field_name].as_i if points
        # else
        #   points =points_yml.find {|x| x["name"] == "default_scoring"}
        #   resp = points[field_name].as_i if points
        # end
      when CNFManager::ResultStatus::Error
        resp = 0
      else
        resp = dynamic_task_points(task, status.to_s.downcase)
      end
      Log.info { "task_points: task: #{task} is worth: #{resp} points" }
      resp
    end

    # Returns what the potential points should be (for a points type of true or false) in order to assign those points to a task
    def self.task_points(task, passed=true)
      if passed
        field_name = "pass"
      else
        field_name = "fail"
      end
      points =points_yml.find {|x| x["name"] == task}
      Log.warn { "****Warning**** task #{task} not found in points.yml".colorize(:yellow) } unless points
      if points && points[field_name]?
          points[field_name].as_i if points
      else
        points =points_yml.find {|x| x["name"] == "default_scoring"}
        points[field_name].as_i if points
      end
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

    # Gets the total assigned points for a tag (or all total points) from the results file
    # Usesful for calculation categories total
    def self.total_points(tag=nil)
      total_points([tag])
    end

    def self.total_points(tags : Array(String) = [] of String)
      if !tags.empty?
        tasks = tasks_by_tag_intersection(tags)
      else
        tasks = all_task_test_names
      end
      yaml = File.open("#{Results.file}") do |file|
        YAML.parse(file)
      end
      Log.debug { "total_points: #{tags}, found tasks: #{tasks}" }
      total = yaml["items"].as_a.reduce(0) do |acc, i|
        Log.debug { "total_points: #{tags}, #{i["name"].as_s} = #{i["points"].as_i}" }
        if i["points"].as_i? && i["name"].as_s? &&
            tasks.find{|x| x == i["name"]}
          (acc + i["points"].as_i)
        else
          acc
        end
      end
      Log.info { "total_points: #{tags} = #{total}" }
      total
    end

    def self.total_passed(tag=nil)
      total_passed([tag])
    end

    def self.total_passed(tags : Array(String) = [] of String)
      Log.debug { "total_passed: #{tags}" }
      if !tags.empty?
        tasks = tasks_by_tag_intersection(tags)
      else
        tasks = all_task_test_names
      end
      yaml = File.open("#{Results.file}") do |file|
        YAML.parse(file)
      end
      Log.debug { "total_points: #{tags}, found tasks: #{tasks}" }
      total = yaml["items"].as_a.reduce(0) do |acc, i|
        Log.debug { "total_points: #{tags}, #{i["name"].as_s} = #{i["points"].as_i}" }
        if i["points"].as_i? && i["points"].as_i > 0 && i["name"].as_s? &&
            tasks.find{|x| x == i["name"]}
          # (acc + i["points"].as_i)
          (acc + 1)
        else
          acc
        end
      end
      Log.info { "total_passed: #{tags} = #{total}" }
      total
    end

    def self.na_assigned?(task)
      yaml = File.open("#{Results.file}") do |file|
        YAML.parse(file)
      end
      assigned = yaml["items"].as_a.find do |i|
        Log.debug { "total_points: #{task}, #{i["name"].as_s} = #{i["points"].as_i} status = #{i["status"]}" }
        if i["name"].as_s? && i["name"].as_s == task && i["status"].as_s? && i["status"] == NA 
          true
        end
      end
      Log.info { "assigned: #{assigned}" }
      assigned 
    end

    # Calculates the total potential points
    def self.total_max_points(tag=nil)
      total_max_points([tag])
    end

    # Calculates the total potential points
    def self.total_max_points(tags : Array(String) = [] of String)
      Log.debug { "total_max_points tag: #{tags}" }
      if !tags.empty?
        tasks = tasks_by_tag_intersection(tags)
      else
        tasks = all_task_test_names
      end

      Log.debug { "tasks - bonus tasks: #{tasks.size}" }

      results_yaml = File.open("#{Results.file}") do |file|
        YAML.parse(file)
      end

      skipped_tests = results_yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        if test_info["status"] == "skipped"
          acc + [test_info["name"].as_s]
        else
          acc
        end
      end

      Log.info { "skipped tests #{skipped_tests}" }

      failed_tests = results_yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        if test_info["status"] == "failed"
          acc + [test_info["name"].as_s]
        else
          acc
        end
      end

      Log.info { "failed tests #{failed_tests}" }

      bonus_tasks = tasks_by_tag("bonus")
      Log.info { "bonus tasks #{bonus_tasks}" }

      max = tasks.reduce(0) do |acc, x|
        Log.info { "task reduce x: #{x}" }
        Log.info { "bonus_tasks.includes?(x) #{bonus_tasks.includes?(x)}" }
        Log.info { "skipped_tests.includes?(x) #{skipped_tests.includes?(x)}" }
        Log.info { "failed_tests.includes?(x) #{failed_tests.includes?(x)}" }
        Log.info { "na_assigned?(x) #{na_assigned?(x)}" }
        if na_assigned?(x)
          Log.info { "na_assigned for #{x}" }
          acc
        elsif bonus_tasks.includes?(x) && (failed_tests.includes?(x) || skipped_tests.includes?(x))
          Log.info { "bonus not counted in maximum #{x}" }
          #don't count failed tests that are bonus tests #1465
          acc
        else
          points = task_points(x)
          if points
            acc + points
          else
            acc
          end
        end
      end
      Log.info { "total_max_points: #{tags} = #{max}" }
      max
    end

    def self.total_max_passed(tag=nil)
      total_max_passed([tag])
    end

    def self.total_max_passed(tags : Array(String) = [] of String)
      Log.debug { "total_max_passed tag: #{tags}" }
      if !tags.empty?
        tasks = tasks_by_tag_intersection(tags)
      else
        tasks = all_task_test_names
      end
      Log.info { "total_max_passed tasks: #{tasks}" }

      results_yaml = File.open("#{Results.file}") do |file|
        YAML.parse(file)
      end

      skipped_tests = results_yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        Log.info { "skipped test_info status: #{test_info["status"]}" }
        if test_info["status"] == "skipped"
          acc + [test_info["name"].as_s]
        else
          acc
        end
      end

      failed_tests = results_yaml["items"].as_a.reduce([] of String) do |acc, test_info|
        if test_info["status"] == "failed"
          acc + [test_info["name"].as_s]
        else
          acc
        end
      end

      Log.info { "failed tests #{failed_tests}" }

      bonus_tasks = tasks_by_tag("bonus")
      Log.info { "bonus tasks #{bonus_tasks}" }

      max = tasks.reduce(0) do |acc, x|
        Log.info { "bonus_tasks.includes?(x) #{bonus_tasks.includes?(x)}" }
        Log.info { "skipped_tests.includes?(x) #{skipped_tests.includes?(x)}" }
        Log.info { "failed_tests.includes?(x) #{failed_tests.includes?(x)}" }
        Log.info { "na_assigned?(x) #{na_assigned?(x)}" }
        Log.info { "tasks x: #{x}" }
        # skipped counted against max score (not reduced), na not counted (reduced)
        if na_assigned?(x)
          Log.info { "na_assigned for #{x}" }
          acc
        elsif bonus_tasks.includes?(x) && (failed_tests.includes?(x) || skipped_tests.includes?(x))
          Log.info { "bonus not counted in maximum #{x}" }
          #don't count failed tests that are bonus tests #1465
          acc
        elsif skipped_tests.includes?(x)
          Log.info { "skipped_assigned for: #{x}" }
          acc + 1 
        else
          points = task_points(x)
          if points
            acc + 1 
          else
            acc
          end
        end
      end
      Log.info { "total_max_passed: #{tags} = #{max}" }
      max
    end


    def self.upsert_task(task, status, points, start_time)
      # In certain cases the results file might not exist.
      # So create one.
      CNFManager::Points::Results.ensure_results_file!

      results = File.open("#{Results.file}") do |f|
        YAML.parse(f)
      end

      result_items = results["items"].as_a
      # remove the existing entry
      result_items = result_items.reject do |x|
        x["name"] == task
      end
      cmd = "#{Process.executable_path} #{ARGV.join(" ")}"
      Log.info {"cmd: #{cmd}"}
      end_time = Time.utc
      task_runtime = (end_time - start_time)

      Log.for("#{task}").info { "task_runtime=#{task_runtime}; start_time=#{start_time}; end_time:#{end_time}" }

      # The task result info has to be appeneded to an array of YAML::Any
      # So encode it into YAML and parse it back again to assign it.
      #
      # Only add task timestamps if the env var is set.
      if ENV.has_key?("TASK_TIMESTAMPS")
        task_result_info = {
          name: task,
          status: status,
          type: task_type_by_task(task),
          points: points,
          start_time: start_time,
          end_time: end_time,
          task_runtime: "#{task_runtime}"
        }
        result_items << YAML.parse(task_result_info.to_yaml)
      else
        task_result_info = {
          name: task,
          status: status,
          type: task_type_by_task(task),
          points: points
        }
        result_items << YAML.parse(task_result_info.to_yaml)
      end

      File.open("#{Results.file}", "w") do |f|
        YAML.dump({name: results["name"],
                   # testsuite_version: CnfTestSuite::VERSION,
                   testsuite_version: ReleaseManager::VERSION,
                   status: results["status"],
                   command: cmd,
                   points: results["points"],
                   exit_code: results["exit_code"],
                   items: result_items}, f)
      end
      Log.info { "upsert_task: task: #{task} has status: #{status} and is awarded: #{points} points. Runtime: #{task_runtime}" }
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
      yaml = File.open("#{Results.file}") do |file|
        YAML.parse(file)
      end
      yaml["items"].as_a.reduce([] of String) do |acc, i|
        if i["status"].as_s == "failed" &&
            i["name"].as_s? &&
            task_required(i["name"].as_s)
          (acc << i["name"].as_s)
        else
          acc
        end
      end
    end

    def self.task_required(task)
      points =points_yml.find {|x| x["name"] == task}
      Log.warn { "task #{task} not found in points.yml".colorize(:yellow) } unless points
      if points && points["required"]? && points["required"].as_bool == true
        true
      else
        false
      end
    end

    def self.all_task_test_names
      result_items =points_yml.reduce([] of String) do |acc, x|
        if x["name"].as_s == "default_scoring" ||
            x["tags"].as_a.find{|x|x=="platform"}
          acc
        else
          acc << x["name"].as_s
        end
      end
    end

    def self.tasks_by_tag(tag)
      result_items = points_yml.reduce([] of String) do |acc, x|
        Log.debug { "tasks_by_tag: tag:#{tag}, points.name:#{x["name"].as_s?}, points.tags:#{x["tags"].as_a?}" }
        if x["tags"].as_a?
          tag_match = x["tags"].as_a.map { |parsed_tag|
            Log.debug { "parsed_tag #{parsed_tag} tag: #{tag}" }
            parsed_tag if parsed_tag == tag.strip
          }.uniq.compact
          Log.debug { "tag_match #{tag_match} name #{x["name"]}" }
          if !tag_match.empty?
            acc << x["name"].as_s
          else
            acc
          end
        else
          acc
        end
      end
    end

    def self.emoji_by_task(task)
      md = points_yml.find {|x| x["name"] == task}
      Log.warn { "****Warning**** task #{task} not found in points.yml".colorize(:yellow) } unless md
      if md && md["emoji"]?
        Log.debug { "task #{task} emoji: #{md["emoji"]?}" }
        resp = md["emoji"]
      else
        resp = ""
      end
    end

    def self.tags_by_task(task)
      points =points_yml.find {|x| x["name"] == task}
      Log.warn { "****Warning**** task #{task} not found in points.yml".colorize(:yellow) } unless points
      Log.info { "points: #{points}" }
      if points && points["tags"]?
          Log.debug { "points tags: #{points["tags"]?}" }
        resp = points["tags"].as_a
      else
        resp = [] of String
      end
          Log.info { "resp: #{resp}" }
      resp
    end

    def self.task_type_by_task(task)
      Log.info {"task_type_by_task"}
      task_type = tags_by_task(task).reduce("") do |acc, x|
        Log.info { "task_type x: #{x} acc: #{acc}" }
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
      Log.info { "task_type: #{task_type}" }
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

    def self.all_result_test_names(results_file)
      results = File.open(results_file) do |f|
        YAML.parse(f)
      end
      result_items = results["items"].as_a.reduce([] of String) do |acc, x|
        acc << x["name"].as_s
      end
    end

    def self.results_by_tag(tag)
      task_list = tasks_by_tag(tag)

      results = File.open("#{Results.file}") do |f|
        YAML.parse(f)
      end

      found = false
      result_items = results["items"].as_a.reduce([] of YAML::Any) do |acc, x|
        if x["name"].as_s? && task_list.find{|tl| tl == x["name"].as_s}
          acc << x
        else
          acc
        end
      end
    end

    def self.template_results_yml
  #TODO add tags for category summaries
  YAML.parse <<-END
name: cnf testsuite
testsuite_version: <%= CnfTestSuite::VERSION %>
status:
points:
exit_code: 0
items: []
END
    end

    def self.final_cnf_results_yml
      Log.info { "final_cnf_results_yml" }
      find_cmd = "find ./results/* -name \"cnf-testsuite-results-*.yml\""
      Process.run(
        find_cmd,
        shell: true,
        output: find_stdout = IO::Memory.new,
        error: find_stderr = IO::Memory.new
      )

      results_file = find_stdout.to_s.split("\n")[-2].gsub("./", "")
      if results_file.empty?
        raise "No cnf_testsuite-results-*.yml found! Did you run the all task?"
      end
      results_file
    end
  end

end
