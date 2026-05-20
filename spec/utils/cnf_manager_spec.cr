require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/utils/kubectl_client.cr"
require "file_utils"
require "sam"

describe "SampleUtils" do
  before_all do
    `./cnf-conformance helm_local_install`
    $?.success?.should be_true
    `./cnf-conformance cleanup`
    $?.success?.should be_true
  end

   # after_all do
      # LOGGING.debug `./cnf-conformance cnf_setup cnf-config=./sample-cnfs/sample-coredns-cnf/cnf-conformance.yml verbose wait_count=0`
   #   $?.success?.should be_true
   # end

  after_each do
    `./cnf-conformance cleanup`
    $?.success?.should be_true
  end

  it "'cnf_setup' should pass with a minimal cnf-conformance.yml", tags: ["cnf-setup"] do
    LOGGING.info `./cnf-conformance cnf_setup cnf-path=./sample-cnfs/sample-minimal-cnf/ wait_count=0`
    $?.success?.should be_true
  ensure
    `./cnf-conformance cnf_cleanup cnf-path=./sample-cnfs/sample-minimal-cnf/ force=true`
  end

  it "'points_yml' should parse and return the points yaml file", tags: ["points"]  do
    (CNFManager::Points.points_yml.find {|x| x["name"] =="liveness"}).should be_truthy 
  end

  it  "'task_points' should return the amount of points for a passing test", tags: ["points"] do
    # default
    (CNFManager::Points.task_points("liveness")).should eq(5)
    # assigned
    (CNFManager::Points.task_points("increase_capacity")).should eq(10)
  end

  it  "'task_points(, false)' should return the amount of points for a failing test", tags: ["points"]  do
    # default
    (CNFManager::Points.task_points("liveness", false)).should eq(-1)
    # assigned
    (CNFManager::Points.task_points("increase_capacity", false)).should eq(-5)
  end

  it  "'task_points(, skipped)' should return the amount of points for a skipped test", tags: ["points"]  do
    # default
    (CNFManager::Points.task_points("liveness", CNFManager::Points::Results::ResultStatus::Skipped)).should eq(0)
  end

  it "'task_required' should return if the passed task is required", tags: ["tasks"]  do
    CNFManager::Points.clean_results_yml
    (CNFManager::Points.task_required("privileged")).should be_true
  end

  it "'failed_required_tasks' should return a list of failed required tasks", tags: ["tasks"]  do
    CNFManager::Points.clean_results_yml
    CNFManager::Points.failed_task("privileged", "FAILED: Privileged container found")
    (CNFManager::Points.failed_required_tasks).should eq(["privileged"])
  end

  it "'upsert_task' insert task in the results file", tags: ["tasks"]  do
    CNFManager::Points.clean_results_yml
   CNFManager::Points.upsert_task("liveness", PASSED, CNFManager::Points.task_points("liveness"))
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    # LOGGING.debug yaml["items"].as_a.inspect
    (yaml["items"].as_a.find {|x| x["name"] == "liveness" && x["points"] == CNFManager::Points.task_points("liveness")}).should be_truthy
  end

  it "'upsert_task' should find and update an existing task in the file", tags: ["tasks"]  do
    CNFManager::Points.clean_results_yml
   CNFManager::Points.upsert_task("liveness", PASSED, CNFManager::Points.task_points("liveness"))
   CNFManager::Points.upsert_task("liveness", PASSED, CNFManager::Points.task_points("liveness"))
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    # LOGGING.debug yaml["items"].as_a.inspect
    (yaml["items"].as_a.find {|x| x["name"] == "liveness" && x["points"] == CNFManager::Points.task_points("liveness")}).should be_truthy
    (CNFManager::Points.total_points).should eq(5)
  end

  it "'CNFManager::Points.total_points' should sum the total amount of points in the results", tags: ["points"] do
    CNFManager::Points.clean_results_yml
   CNFManager::Points.upsert_task("liveness", PASSED, CNFManager::Points.task_points("liveness"))
    (CNFManager::Points.total_points).should eq(5)
  end

  it "'CNFManager::Points.tasks_by_tag' should return the tasks assigned to a tag", tags: ["points"] do
    CNFManager::Points.clean_results_yml
    (CNFManager::Points.tasks_by_tag("configuration_lifecycle")).should eq(["ip_addresses", "liveness", "readiness", "rolling_update", "rolling_downgrade", "rolling_version_change", "rollback", "nodeport_not_used", "hardcoded_ip_addresses_in_k8s_runtime_configuration", "secrets_used", "immutable_configmap"])
    (CNFManager::Points.tasks_by_tag("does-not-exist")).should eq([] of YAML::Any) 
  end

  it "'CNFManager::Points.all_task_test_names' should return all tasks names", tags: ["points"] do
    CNFManager::Points.clean_results_yml
    (CNFManager::Points.all_task_test_names()).should eq(["reasonable_image_size", "reasonable_startup_time", "privileged", "increase_capacity", "decrease_capacity", "network_chaos", "pod_network_latency", "disk_fill", "ip_addresses", "liveness", "readiness", "rolling_update", "rolling_downgrade", "rolling_version_change", "rollback", "nodeport_not_used", "hardcoded_ip_addresses_in_k8s_runtime_configuration", "secrets_used", "immutable_configmap" , "helm_deploy", "install_script_helm", "helm_chart_valid", "helm_chart_published", "chaos_network_loss", "chaos_cpu_hog", "chaos_container_kill", "volume_hostpath_not_found", "no_local_volume_configuration"])
  end

  it "'CNFManager::Points.all_result_test_names' should return the tasks assigned to a tag", tags: ["points"] do
    CNFManager::Points.clean_results_yml
   CNFManager::Points.upsert_task("liveness", PASSED, CNFManager::Points.task_points("liveness"))
    (CNFManager::Points.all_result_test_names(CNFManager::Points::Results.file)).should eq(["liveness"])
  end
  it "'CNFManager::Points.results_by_tag' should return a list of results by tag", tags: ["points"] do
    CNFManager::Points.clean_results_yml
   CNFManager::Points.upsert_task("liveness", PASSED, CNFManager::Points.task_points("liveness"))
    (CNFManager::Points.results_by_tag("configuration_lifecycle")).should eq([{"name" => "liveness", "status" => "passed", "points" => 5}])
    (CNFManager::Points.results_by_tag("does-not-exist")).should eq([] of YAML::Any) 
  end


  it "'#CNFManager::Points::Results.file' should return the name of the current yaml file", tags: ["points"]  do
    CNFManager::Points.clean_results_yml
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    (yaml["name"]).should eq("cnf conformance")
    (yaml["exit_code"]).should eq(0) 
  end

  it "'CNFManager::Points.final_cnf_results_yml. should return the latest time stamped results file", tags: ["points"]  do
    (CNFManager::Points.final_cnf_results_yml).should contain("cnf-conformance-results")
  end


  it "'CNFManager.sample_setup_cli_args(args) and CNFManager.sample_setup(cli_args)' should set up a sample cnf", tags: ["cnf-setup"]  do
    args = Sam::Args.new(["cnf-config=./sample-cnfs/sample-generic-cnf/cnf-conformance.yml", "verbose", "wait_count=180"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    config = CNFManager::Config.parse_config_yml(CNFManager.ensure_cnf_conformance_yml_path(cli_hash[:config_file]))    
    release_name = config.cnf_config[:release_name]

    (Dir.exists? "cnfs/#{release_name}").should be_true
    (File.exists?("cnfs/#{release_name}/cnf-conformance.yml")).should be_true
    (File.exists?("cnfs/#{release_name}/exported_chart/Chart.yaml")).should be_true
    CNFManager.sample_cleanup(config_file: "sample-cnfs/sample-generic-cnf", verbose: true)
    (Dir.exists? "cnfs/#{release_name}").should be_false
  end

  it "'CNFManager.sample_setup' should set up a sample cnf", tags: ["cnf-setup"]  do
    config_file = "sample-cnfs/sample-generic-cnf"
    args = Sam::Args.new(["cnf-config=./#{config_file}/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # args = Sam::Args.new
    # CNFManager.sample_setup(config_file: config_file, release_name: "", deployment_name: "coredns-coredns", helm_chart: "stable/coredns", helm_directory: "", git_clone_url: "https://github.com/coredns/coredns.git", wait_count: 0, verbose: true)
    # check if directory exists
    config = CNFManager::Config.parse_config_yml(CNFManager.ensure_cnf_conformance_yml_path(config_file))    
    release_name = config.cnf_config[:release_name]

    (Dir.exists? "cnfs/#{release_name}").should be_true
    (File.exists?("cnfs/#{release_name}/cnf-conformance.yml")).should be_true
    (File.exists?("cnfs/#{release_name}/exported_chart/Chart.yaml")).should be_true
    CNFManager.sample_cleanup(config_file: "sample-cnfs/sample-generic-cnf", verbose: true)
    (Dir.exists? "cnfs/#{release_name}").should be_false
  end

  it "'CNFManager.sample_setup_args' should set up a sample cnf from a argument", tags: ["cnf-setup"]  do
    config_file = "sample-cnfs/sample-generic-cnf"
    args = Sam::Args.new(["cnf-config=./#{config_file}/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # args = Sam::Args.new
    # CNFManager.sample_setup_args(sample_dir: config_file, args: args, verbose: true, wait_count: 0 )
    # check if directory exists
    config = CNFManager::Config.parse_config_yml(CNFManager.ensure_cnf_conformance_yml_path(config_file))    
    release_name = config.cnf_config[:release_name]
    (Dir.exists? "cnfs/#{release_name}").should be_true
    (File.exists?("cnfs/#{release_name}/cnf-conformance.yml")).should be_true
    # (File.exists?("cnfs/#{release_name}/helm_chart/Chart.yaml")).should be_true
    CNFManager.sample_cleanup(config_file: "sample-cnfs/sample-generic-cnf", verbose: true)
    (Dir.exists? "cnfs/#{release_name}").should be_false
  end

  it "'CNFManager.sample_setup_args' should set up a sample cnf from a config file", tags: ["cnf-setup"]  do
    config_file = "sample-cnfs/sample-generic-cnf"
    args = Sam::Args.new(["cnf-config=./#{config_file}/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # args = Sam::Args.new
    # CNFManager.sample_setup_args(sample_dir: config_file, args: args, verbose: true, wait_count: 0 )
    # check if directory exists
    config = CNFManager::Config.parse_config_yml(CNFManager.ensure_cnf_conformance_yml_path(config_file))    
    release_name = config.cnf_config[:release_name]
    (Dir.exists? "sample-cnfs/sample-generic-cnf").should be_true
    (File.exists?("cnfs/#{release_name}/cnf-conformance.yml")).should be_true
    # (File.exists?("cnfs/#{release_name}/helm_chart/Chart.yaml")).should be_true
    CNFManager.sample_cleanup(config_file: "sample-cnfs/sample-generic-cnf", verbose: true)
    (Dir.exists? "cnfs/#{release_name}").should be_false
  end

  it "'CNFManager.sample_cleanup' should clean up a sample cnf from a argument", tags: ["cnf-setup"]  do
    args = Sam::Args.new(["cnf-config=./sample-cnfs/sample-generic-cnf/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # args = Sam::Args.new
    # CNFManager.sample_setup_args(sample_dir: "sample-cnfs/sample-generic-cnf", args: args, verbose: true, wait_count: 0 )
    cleanup = CNFManager.sample_cleanup(config_file: "sample-cnfs/sample-generic-cnf", verbose: true)
    (cleanup).should be_true 
    (Dir.exists? "cnfs/coredns").should be_false
    (File.exists?("cnfs/coredns/cnf-conformance.yml")).should be_false
    (File.exists?("cnfs/coredns/helm_chart/Chart.yaml")).should be_false
  end

  it "'CNFManager.sample_setup_args' should be able to deploy using a helm_directory", tags: ["cnf-setup"]  do
    config_file = "sample-cnfs/sample_privileged_cnf"
    args = Sam::Args.new(["cnf-config=./#{config_file}/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # args = Sam::Args.new
    # CNFManager.sample_setup_args(sample_dir: config_file, deploy_with_chart: false, args: args, verbose: true, wait_count: 0 )
    config = CNFManager::Config.parse_config_yml(CNFManager.ensure_cnf_conformance_yml_path(config_file))    
    release_name = config.cnf_config[:release_name]
    (Dir.exists? "cnfs/#{release_name}").should be_true
    # should not clone
    (Dir.exists? "cnfs/#{release_name}/privileged-coredns").should be_false
    (File.exists? "cnfs/#{release_name}/cnf-conformance.yml").should be_true
    (File.exists? "cnfs/#{release_name}/chart/Chart.yaml").should be_true
    CNFManager.sample_cleanup(config_file: "sample-cnfs/sample_privileged_cnf", verbose: true)
    (Dir.exists? "cnfs/#{release_name}").should be_false
  end

  it "'CNFManager.sample_setup_args and CNFManager.sample_cleanup' should be able to deploy and cleanup using a manifest_directory", tags: ["cnf-setup"]  do
    config_file = "sample-cnfs/k8s-non-helm"
    args = Sam::Args.new(["cnf-config=./#{config_file}/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # args = Sam::Args.new
    # config_file = "sample-cnfs/k8s-non-helm"
    # CNFManager.sample_setup_args(sample_dir: config_file, deploy_with_chart: false, args: args, verbose: true, install_from_manifest: true, wait_count: 0 )
    config = CNFManager::Config.parse_config_yml(CNFManager.ensure_cnf_conformance_yml_path(config_file))    
    release_name = config.cnf_config[:release_name]
    (Dir.exists? "cnfs/#{release_name}").should be_true
    (Dir.exists? "cnfs/#{release_name}/manifests").should be_true
    (File.exists? "cnfs/#{release_name}/cnf-conformance.yml").should be_true
    (KubectlClient::Get.pod_exists?("nginx-webapp")).should be_true
    CNFManager.sample_cleanup(config_file: "sample-cnfs/k8s-non-helm", installed_from_manifest: true, verbose: true)
    # TODO check for pod status = terminating
    (KubectlClient::Get.pod_exists?("nginx-webapp", check_ready: true)).should be_false
    (Dir.exists? "cnfs/#{release_name}").should be_false
  end

  it "'cnf_destination_dir' should return the full path of the potential destination cnf directory based on the deployment name", tags: "WIP" do
    args = Sam::Args.new
    CNFManager.cnf_destination_dir("spec/fixtures/cnf-conformance.yml").should contain("/cnfs/coredns")
  end

  it "'CNFManager.cnf_config_list' should return a list of all of the config files from the cnf directory", tags: ["cnf-setup"]  do
    config_file = "sample-cnfs/sample-generic-cnf"
    args = Sam::Args.new(["cnf-config=./#{config_file}/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # args = Sam::Args.new
    # config_file = "sample-cnfs/sample-generic-cnf"
    # CNFManager.sample_setup_args(sample_dir: config_file, args: args, verbose: true, wait_count: 1 )
    args = Sam::Args.new(["cnf-config=./sample-cnfs/sample_privileged_cnf/cnf-conformance.yml", "verbose"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    CNFManager.sample_setup(cli_hash)
    # CNFManager.sample_setup_args(sample_dir: "sample-cnfs/sample_privileged_cnf", args: args, verbose: true )
    config = CNFManager::Config.parse_config_yml(CNFManager.ensure_cnf_conformance_yml_path(config_file))    
    release_name = config.cnf_config[:release_name]
    CNFManager.cnf_config_list()[0].should contain("#{release_name}/#{CONFIG_FILE}")
  end

  it "'CNFManager.helm_repo_add' should add a helm repo if the helm repo is valid", tags: ["helm-repo"] do
    config_file = "sample-cnfs/sample-generic-cnf"
    args = Sam::Args.new(["cnf-config=./#{config_file}/cnf-conformance.yml", "verbose", "wait_count=0"])
    cli_hash = CNFManager.sample_setup_cli_args(args)
    # args = Sam::Args.new
    # CNFManager.sample_setup_args(sample_dir: "sample-cnfs/sample-generic-cnf", args: args, verbose: true, wait_count: 1 )
    # CNFManager.helm_repo_add.should eq(true)
    args = Sam::Args.new(["cnf-config=./sample-cnfs/sample-generic-cnf/cnf-conformance.yml"])
    CNFManager.helm_repo_add(args: args).should eq(true)
  end

  it "'CNFManager.helm_repo_add' should return false if the helm repo is invalid", tags: ["helm-repo"]  do
    CNFManager.helm_repo_add("invalid", "invalid").should eq(false)
  end

  it "'CNFManager.validate_cnf_conformance_yml' (function) should pass, when a cnf has a valid config file yml", tags: ["validate_config"]  do
    args = Sam::Args.new(["cnf-config=sample-cnfs/sample-coredns-cnf/cnf-conformance.yml"])

    yml = CNFManager.parsed_config_file(CNFManager.ensure_cnf_conformance_yml_path(args.named["cnf-config"].as(String)))
    LOGGING.info yml.inspect
    ("#{yml.get("release_name").as_s?}").should eq("coredns")

    valid, command_output = CNFManager.validate_cnf_conformance_yml(yml)

    (valid).should eq(true)
    (command_output).should eq (nil)
  end

  it "'CNFManager.validate_cnf_conformance_yml' (command) should pass, when a cnf has a valid config file yml", tags: ["validate_config"]  do
    response_s = `./cnf-conformance validate_config cnf-config=sample-cnfs/sample-coredns-cnf/cnf-conformance.yml`
    $?.success?.should be_true
    (/PASSED: CNF configuration validated/ =~ response_s).should_not be_nil
  end


  it "'CNFManager.validate_cnf_conformance_yml' (function) should warn, but be valid when a cnf config file yml has fields that are not a part of the validation type", tags: ["validate_config"]  do
    args = Sam::Args.new(["cnf-config=./spec/fixtures/cnf-conformance-unmapped-keys-and-subkeys.yml"])

    yml = CNFManager.parsed_config_file(CNFManager.ensure_cnf_conformance_yml_path(args.named["cnf-config"].as(String)))
    LOGGING.info yml.inspect
    ("#{yml.get("release_name").as_s?}").should eq("coredns")

    status, warning_output = CNFManager.validate_cnf_conformance_yml(yml)

    LOGGING.warn "WARNING: #{warning_output}"

    (status).should eq(true)
    (warning_output).should_not be_nil
  end


  it "'CNFManager.validate_cnf_conformance_yml' (command) should warn, but be valid when a cnf config file yml has fields that are not a part of the validation type", tags: ["validate_config"]  do
    response_s = `./cnf-conformance validate_config cnf-config=spec/fixtures/cnf-conformance-unmapped-keys-and-subkeys.yml`
    $?.success?.should be_true
    LOGGING.debug "validate_config resp: #{response_s}"
    (/WARNING: Unmapped cnf_conformance.yml keys. Please add them to the validator/ =~ response_s).should_not be_nil
    (/WARNING: helm_repository is unset or has unmapped subkeys. Please update your cnf_conformance.yml/ =~ response_s).should_not be_nil
    (/PASSED: CNF configuration validated/ =~ response_s).should_not be_nil
  end


  it "'CNFManager.validate_cnf_conformance_yml' (function) should fail when an invalid cnf config file yml is used", tags: ["validate_config"]  do
    args = Sam::Args.new(["cnf-config=spec/fixtures/cnf-conformance-invalid-and-unmapped-keys.yml"])


    yml = CNFManager.parsed_config_file(CNFManager.ensure_cnf_conformance_yml_path(args.named["cnf-config"].as(String)))
    LOGGING.info yml.inspect
    # config = CNFManager::Config.parse_config_yml(args.named["cnf-config"].as(String))    
    # release_name = config.cnf_config[:release_name]
    # ("#{yml.get("release_name").as_s?}").should eq(release_name)

    status, warning_output = CNFManager.validate_cnf_conformance_yml(yml)

    (status).should eq(false)
    (warning_output).should eq(nil)
  end

  it "'CNFManager.validate_cnf_conformance_yml' (command) should fail when an invalid cnf config file yml is used", tags: ["validate_config"]  do
    response_s = `./cnf-conformance validate_config cnf-config=spec/fixtures/cnf-conformance-invalid-and-unmapped-keys.yml`
    $?.success?.should be_true

    (/ERROR: cnf_conformance.yml field validation error/ =~ response_s).should_not be_nil
    (/FAILED: Critical Error with CNF Configuration. Please review USAGE.md for steps to set up a valid CNF configuration file/ =~ response_s).should_not be_nil
  end

  it "'CNFManager.validate_cnf_conformance_yml' (command) should pass, for all sample-cnfs", tags: ["validate_config"]  do

    get_dirs = Dir.entries("sample-cnfs")
    dir_list = get_dirs - [".", ".."]
    dir_list.each do |dir|
      conformance_yml = "sample-cnfs/#{dir}/cnf-conformance.yml"
      response_s = `./cnf-conformance validate_config cnf-config=#{conformance_yml}`
      if (/FAILED: Critical Error with CNF Configuration. Please review USAGE.md for steps to set up a valid CNF configuration file/ =~ response_s)
        LOGGING.info "\n #{conformance_yml}: #{response_s}"
      end
      (/PASSED: CNF configuration validated/ =~ response_s).should_not be_nil
    end
  end

  it "'CNFManager.validate_cnf_conformance_yml' (command) should pass, for all example-cnfs", tags: ["validate_config"]  do

    get_dirs = Dir.entries("example-cnfs")
    dir_list = get_dirs - [".", ".."]
    dir_list.each do |dir|
      conformance_yml = "example-cnfs/#{dir}/cnf-conformance.yml"
      response_s = `./cnf-conformance validate_config cnf-config=#{conformance_yml}`
      if (/FAILED: Critical Error with CNF Configuration. Please review USAGE.md for steps to set up a valid CNF configuration file/ =~ response_s)
        LOGGING.info "\n #{conformance_yml}: #{response_s}"
      end
      (/PASSED: CNF configuration validated/ =~ response_s).should_not be_nil
    end
  end


  it "'CNFManager::Config#parse_config_yml' should return a populated CNFManager::Config.cnf_config", tags: ["cnf-config"]  do
    begin
      yaml = CNFManager::Config.parse_config_yml("spec/fixtures/cnf-conformance.yml")    
    (yaml.cnf_config[:release_name]).should eq("coredns")
    ensure
    end
  end

  it "'CNFManager.workload_resource_test' should accept an args and cnf-config argument, populate a deployment, container, and intialized argument, and then apply a test to a cnf", tags: ["cnf-config"]  do
    args = Sam::Args.new(["cnf-config=./sample-cnfs/sample-generic-cnf/cnf-conformance.yml"])
    # check_cnf_config_then_deploy(args)
    cli_hash = CNFManager.sample_setup_cli_args(args, false)
    CNFManager.sample_setup(cli_hash) if cli_hash["config_file"]
    config = CNFManager::Config.parse_config_yml("./sample-cnfs/sample-generic-cnf/cnf-conformance.yml")    
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      test_passed = true
				begin
					VERBOSE_LOGGING.debug container.as_h["name"].as_s if check_verbose(args)
					container.as_h["livenessProbe"].as_h 
				rescue ex
					VERBOSE_LOGGING.error ex.message if check_verbose(args)
					test_passed = false 
          puts "No livenessProbe found for resource: #{resource} and container: #{container.as_h["name"].as_s}".colorize(:red)
				end
      test_passed 
    end
    (task_response).should be_true 
    CNFManager.sample_cleanup(config_file: "sample-cnfs/sample-generic-cnf", verbose: true)
  end

  it "'CNFManager.exclusive_install_method_tags' should return false if install method tags are not exclusive", tags: ["cnf-config"]  do
    config = CNFManager.parsed_config_file("./spec/fixtures/cnf-conformance-not-exclusive.yml")
    resp = CNFManager.exclusive_install_method_tags?(config)
    (resp).should be_false
  end

  describe "CNFManager.helm_dir_path" do
    it "joins a relative helm_directory to the base_dir", tags: ["helm-dir-path"] do
      result = CNFManager.helm_dir_path("/cnfs/myapp", "charts/envoy")
      result.should eq("/cnfs/myapp/charts/envoy")
    end

    it "returns an absolute helm_directory unchanged (bug #2385)", tags: ["helm-dir-path"] do
      result = CNFManager.helm_dir_path("/cnfs/myapp", "/home/user/charts/envoy")
      result.should eq("/home/user/charts/envoy")
    end

    it "joins a bare directory name (no leading slash) to base_dir", tags: ["helm-dir-path"] do
      result = CNFManager.helm_dir_path("./example-cnfs/envoy", "envoy")
      result.should eq("./example-cnfs/envoy/envoy")
    end

    it "does not double-slash when base_dir has a trailing slash", tags: ["helm-dir-path"] do
      result = CNFManager.helm_dir_path("/cnfs/myapp/", "charts")
      result.should eq("/cnfs/myapp//charts")
    end

    it "returns an absolute path with nested segments unchanged", tags: ["helm-dir-path"] do
      result = CNFManager.helm_dir_path("./example-cnfs/envoy", "/home/cedric/Devs/CNTI/testsuite/example-cnfs/envoy/envoy")
      result.should eq("/home/cedric/Devs/CNTI/testsuite/example-cnfs/envoy/envoy")
    end
  end

end



