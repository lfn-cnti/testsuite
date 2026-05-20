# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "The CNF conformance suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s kubectl"
task "installability", ["install_script_helm", "helm_chart_valid", "helm_chart_published", "helm_deploy"] do |_, args|
  stdout_score("installability")
end

desc "Will the CNF install using helm with helm_deploy?"
task "helm_deploy" do |_, args|
  unless check_destructive(args)
    LOGGING.info "skipping helm_deploy: not in destructive mode"
    puts "SKIPPED: Helm Deploy".colorize(:yellow)
    next
  end
  LOGGING.info "Running helm_deploy in destructive mode!"
  VERBOSE_LOGGING.info "helm_deploy" if check_verbose(args)
  LOGGING.info("helm_deploy args: #{args.inspect}")
  if check_cnf_config(args) || CNFManager.destination_cnfs_exist?
    CNFManager::Task.task_runner(args) do |args, config|
      begin
        # TODO if manifest file and not helm, fail
        # TODO helm should template the metadata.name attribute based on the helm release name
        # TODO if we dont detect a templated metadata.name, use a namespace
        # TODO do something if using rbac roles since they cant be namespaced
        release_name_prefix = "helm-deploy-"
        create_namespace = `kubectl create namespace helm-deploy`

        helm_chart = config.cnf_config[:helm_chart]
        helm_directory = config.cnf_config[:helm_directory]
        release_name = config.cnf_config[:release_name]
        yml_file_path = config.cnf_config[:yml_file_path]

        current_dir = FileUtils.pwd

        helm = CNFSingleton.helm
        VERBOSE_LOGGING.debug helm if check_verbose(args)

        if helm_chart.empty?
          VERBOSE_LOGGING.debug "#{helm} install --namespace helm-deploy #{release_name_prefix}#{release_name} #{CNFManager.helm_dir_path(yml_file_path, helm_directory)}" if check_verbose(args)
          helm_install = `#{helm} install --namespace helm-deploy #{release_name_prefix}#{release_name} #{CNFManager.helm_dir_path(yml_file_path, helm_directory)}`
        else
          VERBOSE_LOGGING.debug "#{helm} install --namespace helm-deploy #{release_name_prefix}#{release_name} #{helm_chart}" if check_verbose(args)
          helm_install = `#{helm} install --namespace helm-deploy #{release_name_prefix}#{release_name} #{helm_chart}`
        end

        is_helm_installed = $?.success?
        VERBOSE_LOGGING.info helm_install if check_verbose(args)

        if is_helm_installed
          upsert_passed_task("helm_deploy", "✔️  PASSED: Helm deploy successful")
        else
          upsert_failed_task("helm_deploy", "✖️  FAILED: Helm deploy failed")
        end
      ensure
        VERBOSE_LOGGING.debug "#{helm} uninstall --namespace helm-deploy #{release_name_prefix}#{release_name}" if check_verbose(args)
        helm_uninstall = `#{helm} uninstall --namespace helm-deploy #{release_name_prefix}#{release_name}`
        delete_namespace = `kubectl delete namespace helm-deploy`
      end
    end
  else
    upsert_failed_task("helm_deploy", "✖️  FAILED: No cnf_conformance.yml found! Did you run the setup task?")
  end
end

desc "Does the install script use helm?"
task "install_script_helm" do |_, args|
  CNFManager::Task.task_runner(args) do |args, config|
    # config = CNFManager.parsed_config_file(CNFManager.ensure_cnf_conformance_yml_path(args.named["cnf-config"].as(String)))

    found = 0
    # destination_cnf_dir = CNFManager.cnf_destination_dir(CNFManager.ensure_cnf_conformance_dir(args.named["cnf-config"].as(String)))
    # install_script = config.get("install_script").as_s?
    install_script = config.cnf_config[:install_script]
    LOGGING.info "install_script: #{install_script}"
    destination_cnf_dir = config.cnf_config[:destination_cnf_dir]
    LOGGING.info "destination_cnf_dir: #{destination_cnf_dir}"
    VERBOSE_LOGGING.debug destination_cnf_dir if check_verbose(args)
    if !install_script.empty?
      response = String::Builder.new
      content = File.open("#{destination_cnf_dir}/#{install_script}") do |file|
        file.gets_to_end
      end
      # LOGGING.debug content
      if /helm/ =~ content
        found = 1
      end
      if found < 1
        upsert_failed_task("install_script_helm", "✖️  FAILED: Helm not found in supplied install script")
      else
        upsert_passed_task("install_script_helm", "✔️  PASSED: Helm found in supplied install script")
      end
    else
      upsert_passed_task("install_script_helm", "✔️  PASSED (by default): No install script provided")
    end
  end
end

task "helm_chart_published", ["helm_local_install"] do |_, args|
  CNFManager::Task.task_runner(args) do |args, config|
    VERBOSE_LOGGING.info "helm_chart_published" if check_verbose(args)
    VERBOSE_LOGGING.debug "helm_chart_published args.raw: #{args.raw}" if check_verbose(args)
    VERBOSE_LOGGING.debug "helm_chart_published args.named: #{args.named}" if check_verbose(args)

    # config = cnf_conformance_yml
    # config = CNFManager.parsed_config_file(CNFManager.ensure_cnf_conformance_yml_path(args.named["cnf-config"].as(String)))
    # helm_chart = "#{config.get("helm_chart").as_s?}"
    helm_chart = config.cnf_config[:helm_chart]

    current_dir = FileUtils.pwd
    helm = CNFSingleton.helm
    VERBOSE_LOGGING.debug helm if check_verbose(args)

    if CNFManager.helm_repo_add(args: args)
      unless helm_chart.empty?
        helm_search = `#{helm} search repo #{helm_chart}`
        LOGGING.info "helm search command: #{helm} search repo #{helm_chart}"
        VERBOSE_LOGGING.debug "#{helm_search}" if check_verbose(args)
        unless helm_search =~ /No results found/
          upsert_passed_task("helm_chart_published", "✔️  PASSED: Published Helm Chart Found")
        else
          upsert_failed_task("helm_chart_published", "✖️  FAILED: Published Helm Chart Not Found")
        end
      else
        upsert_failed_task("helm_chart_published", "✖️  FAILED: Published Helm Chart Not Found")
      end
    else
      upsert_failed_task("helm_chart_published", "✖️  FAILED: Published Helm Chart Not Found")
    end
  end
end

task "helm_chart_valid", ["helm_local_install"] do |_, args|
  CNFManager::Task.task_runner(args) do |args|
    VERBOSE_LOGGING.info "helm_chart_valid" if check_verbose(args)
    VERBOSE_LOGGING.debug "helm_chart_valid args.raw: #{args.raw}" if check_verbose(args)
    VERBOSE_LOGGING.debug "helm_chart_valid args.named: #{args.named}" if check_verbose(args)

    response = String::Builder.new

    config = CNFManager.parsed_config_file(CNFManager.ensure_cnf_conformance_yml_path(args.named["cnf-config"].as(String)))
    # helm_directory = config.get("helm_directory").as_s
    helm_directory = optional_key_as_string(config, "helm_directory")
    if helm_directory.empty?
      working_chart_directory = "exported_chart"
    else
      working_chart_directory = helm_directory
    end

    if args.named.keys.includes? "cnf_chart_path"
      working_chart_directory = args.named["cnf_chart_path"]
    end

    VERBOSE_LOGGING.debug "working_chart_directory: #{working_chart_directory}" if check_verbose(args)

    current_dir = FileUtils.pwd
    VERBOSE_LOGGING.debug current_dir if check_verbose(args)
    helm = CNFSingleton.helm

    destination_cnf_dir = CNFManager.cnf_destination_dir(CNFManager.ensure_cnf_conformance_dir(args.named["cnf-config"].as(String)))

    helm_lint = `#{helm} lint #{destination_cnf_dir}/#{working_chart_directory}`
    VERBOSE_LOGGING.debug "helm_lint: #{helm_lint}" if check_verbose(args)

    if $?.success?
      upsert_passed_task("helm_chart_valid", "✔️  PASSED: Helm Chart #{working_chart_directory} Lint Passed")
    else
      upsert_failed_task("helm_chart_valid", "✖️  FAILED: Helm Chart #{working_chart_directory} Lint Failed")
    end
  end
end

task "validate_config" do |_, args|
  yml = CNFManager.parsed_config_file(CNFManager.ensure_cnf_conformance_yml_path(args.named["cnf-config"].as(String)))
  valid, warning_output = CNFManager.validate_cnf_conformance_yml(yml)
  emoji_config="📋"
  if valid
    stdout_success "✔️ PASSED: CNF configuration validated #{emoji_config}"
  else
    stdout_failure "❌ FAILED: Critical Error with CNF Configuration. Please review USAGE.md for steps to set up a valid CNF configuration file #{emoji_config}"
  end
end
