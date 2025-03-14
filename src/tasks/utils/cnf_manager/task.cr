require "totem"
require "colorize"
require "helm"
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
                         &block : (Sam::Args, CNFInstall::Config::Config) -> (
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
                                  &block : (Sam::Args, CNFInstall::Config::Config) -> (
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
                                &block : (Sam::Args, CNFInstall::Config::Config) -> (
                                  String | Colorize::Object(String) | CNFManager::TestCaseResult?)
    )
      logger = @@logger.for("task_runner")
      logger.debug { "Run task with args #{args.inspect}" }

      begin
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

        test_start_time = Time.utc
        if task
          test_name = task.as(Sam::Task).name.as(String)
          logger.for(test_name).info { "Starting test" }
          stdout_info("🎬 Testing: [#{test_name}]")
        end

        ret = yield args, config
        if ret.is_a?(CNFManager::TestCaseResult)
          upsert_decorated_task(test_name, ret.state, ret.result_message, test_start_time)
        end
        # todo lax mode, never returns 1
        if args.raw.includes? "strict"
          if CNFManager::Points.failed_required_tasks.size > 0
            logger.fatal { "Strict mode exception. Stopping execution." }
            stdout_failure "Test Suite failed in strict mode. Stopping execution."
            stdout_failure "Failed required tasks: #{CNFManager::Points.failed_required_tasks.inspect}"
            update_yml("#{CNFManager::Points::Results.file}", "exit_code", "#{FAILURE_CODE}")
            exit FAILURE_CODE
          end
        end
        ret
      rescue ex
        # platform tests don't have a cnf-config
        # Set exception key/value in results
        # file to -1
        test_start_time = Time.utc
        logger.error { ex.message }
        ex.backtrace.each do |x|
          logger.error { x }
        end

        update_yml("#{CNFManager::Points::Results.file}", "exit_code", "#{CRITICAL_FAILURE_CODE}")
        if args.raw.includes? "strict"
          logger.fatal { "Strict mode exception. Stopping execution." }
          stdout_failure "Test Suite failed in strict mode. Stopping execution."
          exit CRITICAL_FAILURE_CODE
        else
          logger.warn { "Exception caught, continue to the next task" }
          upsert_decorated_task(test_name, CNFManager::ResultStatus::Error, 
            "Unexpected error occurred", test_start_time)
        end
      end
    end
  end
end
