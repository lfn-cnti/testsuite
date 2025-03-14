require "totem"
require "colorize"
require "helm"
require "uuid"
require "./points.cr"

module CNFManager 

  module Task
    FAILURE = 1
    CRITICAL_FAILURE = 2

    def self.ensure_cnf_installed!

      cnf_installed = CNFManager.cnf_installed?

      Log.info { "ensure_cnf_installed?  #{cnf_installed}" }
      
      unless cnf_installed
        puts "You must install a CNF first.".colorize(:yellow)
        exit 1
      end
    end

    def self.task_runner(args, task : Sam::Task|Nil=nil, check_cnf_installed=true, &block : Sam::Args, CNFInstall::Config::Config -> String | Colorize::Object(String) | CNFManager::TestcaseResult | Nil)
      Log.info { "task_runner args: #{args.inspect}" }

      CNFManager::Points::Results.ensure_results_file!

      if check_cnf_installed
        ensure_cnf_installed!
      end

      if check_cnf_config(args)
        single_task_runner(args, task, &block)
      else
        all_cnfs_task_runner(args, task, &block)
      end
    end

    # TODO give example for calling
    def self.all_cnfs_task_runner(args, task : Sam::Task|Nil=nil, &block : Sam::Args, CNFInstall::Config::Config  -> String | Colorize::Object(String) | CNFManager::TestcaseResult | Nil)
      cnf_configs = CNFManager.cnf_config_list(silent: true)
      Log.info { "CNF configs found: #{cnf_configs.size}" }

      # Platforms tests dont have any cnfs
      if cnf_configs.size == 0
        single_task_runner(args, &block)
      else
        cnf_configs.map do |x|
          new_args = Sam::Args.new(args.named, args.raw)
          new_args.named["cnf-config"] = x
          single_task_runner(new_args, task, &block)
        end
      end
    end

    # TODO give example for calling
    def self.single_task_runner(args, task : Sam::Task|Nil=nil, &block : Sam::Args, CNFInstall::Config::Config -> String | Colorize::Object(String) | CNFManager::TestcaseResult | Nil)
      Log.debug { "single_task_runner args: #{args.inspect}" }

      begin
        if args.named["cnf-config"]? # platform tests don't have a cnf-config
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
          Log.for(test_name).info { "Starting test" }
          Log.for(test_name).debug { "cnf_config: #{config}" }
          puts "🎬 Testing: [#{test_name}]"
        end
        ret = yield args, config
        if ret.is_a?(CNFManager::TestcaseResult)
          upsert_decorated_task(test_name, ret.state, ret.result_message, test_start_time)
        end
        #todo lax mode, never returns 1
        if args.raw.includes? "strict"
          if CNFManager::Points.failed_required_tasks.size > 0
            stdout_failure "Test Suite failed in strict mode. Stopping executing."
            stdout_failure "Failed required tasks: #{CNFManager::Points.failed_required_tasks.inspect}"
            update_yml("#{CNFManager::Points::Results.file}", "exit_code", "1")
            exit 1
          end
        end
        ret
      rescue ex
        # platform tests don't have a cnf-config
        # Set exception key/value in results
        # file to -1
        test_start_time = Time.utc
        Log.error { ex.message }
        ex.backtrace.each do |x|
          Log.error { x }
        end
        
        update_yml("#{CNFManager::Points::Results.file}", "exit_code", "2")
        if args.raw.includes? "strict" 
          Log.info { "Strict mode exception.  Stopping execution." }
          exit 2
        else
          Log.info { "exception with skipped exit code" }
          upsert_decorated_task(test_name, CNFManager::ResultStatus::Error, "Unexpected error occurred", test_start_time)
        end
      end
    end
  end
end
