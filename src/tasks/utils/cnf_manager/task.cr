require "totem"
require "colorize"
require "../../../modules/helm"
require "uuid"
require "./points.cr"

module CNFManager
  module Task
    @@logger : ::Log = Log.for("Task")

    FAILURE_CODE          = 1
    CRITICAL_FAILURE_CODE = 2

    def self.ensure_cnf_installed!
      cnf_installed = CNFManager.cnf_installed?
      @@logger.for("ensure_cnf_installed!").info { "Is CNF installed: #{cnf_installed}" }

      unless cnf_installed
        stdout_warning("You must install a CNF first.")
        exit FAILURE_CODE
      end
    end

    def self.task_runner(args, task : Sam::Task? = nil, check_cnf_installed = true,
                         &block : (Sam::Args, CNFInstall::Config::Config, CNFManager::TestCaseResult) -> (
                           String | Colorize::Object(String) | CNFManager::TestCaseResult?)
    )
      CNFManager::Points::Results.ensure_results_file!
      ensure_cnf_installed!() if check_cnf_installed

      if check_cnf_config(args)
        single_task_runner(args, task, &block)
      else
        all_cnfs_task_runner(args, task, &block)
      end
    end

    def self.all_cnfs_task_runner(args, task : Sam::Task? = nil,
                                  &block : (Sam::Args, CNFInstall::Config::Config, CNFManager::TestCaseResult) -> (
                                    String | Colorize::Object(String) | CNFManager::TestCaseResult?)
    )
      cnf_configs = CNFManager.cnf_config_list(false)

      # Platforms tests dont have any CNFs
      if cnf_configs.empty?
        single_task_runner(args, &block)
      else
        cnf_configs.map do |config|
          new_args = Sam::Args.new(args.named, args.raw)
          new_args.named["cnf-config"] = config
          single_task_runner(new_args, task, &block)
        end
      end
    end

    # TODO give example for calling
    def self.single_task_runner(args, task : Sam::Task? = nil, 
                                &block : (Sam::Args, CNFInstall::Config::Config, CNFManager::TestCaseResult) -> (
                                  String | Colorize::Object(String) | CNFManager::TestCaseResult?)
    )
      logger = @@logger.for("task_runner")
      logger.debug { "Run task with args #{args.inspect}" }

      # platform tests don't have a cnf-config
      if args.named["cnf-config"]?
        config = CNFInstall::Config.parse_cnf_config_from_file(args.named["cnf-config"].as(String))
      else
        yaml_string = <<-YAML
          config_version: v2
          deployments:
            helm_dirs:
              - name: "platform-test-dummy-deployment"
                helm_directory: ""
          YAML
        config = CNFInstall::Config.parse_cnf_config_from_yaml(yaml_string)
      end

      result = CNFManager::TestCaseResult.empty
      result.set_start_time()
      if task
        result.set_testcase(task.as(Sam::Task).name.as(String))
        logger.for(result.testcase).info { "Starting test" }
        stdout_info("🎬 Testing: [#{result.testcase}]")
      end

      begin
        yield args, config, result
      rescue ex
        result.error("Unexpected error occurred")
        logger.error { ex.message }
        ex.backtrace.each do |x|
          logger.error { x }
        end
      ensure
        result.set_end_time()
        upsert_decorated_task(result)
      end

      # todo lax mode, never returns 1
      if args.raw.includes? "strict"
        if result.status == CNFManager::ResultStatus::Error || result.status == CNFManager::ResultStatus::Failed
          logger.fatal { "Strict mode exception. Stopping execution." }
          stdout_failure "Test Suite failed in strict mode. Stopping execution."
          if CNFManager::Points.failed_required_tasks.size > 0
            stdout_failure "Failed required tasks: #{CNFManager::Points.failed_required_tasks.inspect}"
          end
          exit_code = result.status == CNFManager::ResultStatus::Error ? CRITICAL_FAILURE_CODE : FAILURE_CODE
          update_yml("#{CNFManager::Points::Results.file}", "exit_code", "#{exit_code}")
          exit exit_code
        end
      end
    end
  end
end
