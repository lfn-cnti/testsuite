# coding: utf-8
require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/setup/helmenv_setup.cr"
require "file_utils"
require "sam"
require "json"
require "http/server"

describe "Utils" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true

    # Ensure a results file is present to test different scenarios
    CNFManager::Points::Results.ensure_results_file!
  end

  before_each do
    result = ShellCmd.run_testsuite("delete_results")
  end
  after_each do
    result = ShellCmd.run_testsuite("delete_results")
  end

  it "'toggle' should return a boolean for a toggle in the config.yml", tags: ["args"] do
    (toggle("wip")).should eq(false) 
  end

  it "'check_feature_level' should return the feature level for an argument variable", tags: ["args"]  do
    args = Sam::Args.new(["name", "arg1=1", "beta"])
    (check_feature_level(args)).should eq("beta")
    args = Sam::Args.new(["name", "arg1=1", "alpha"])
    (check_feature_level(args)).should eq("alpha")
    args = Sam::Args.new(["name", "arg1=1", "wip"])
    (check_feature_level(args)).should eq("wip")
    args = Sam::Args.new(["name", "arg1=1", "hi"])
    (check_feature_level(args)).should eq("ga")

  end

  it "'check_<x>' should return the feature level for an argument variable", tags: ["args"]  do
    (check_alpha).should be_false
    (check_beta).should be_false
    (check_wip).should be_false
  end

  it "'check_<x>(args)' should return the feature level for an argument variable", tags: ["args"]  do
    args = Sam::Args.new(["name", "arg1=1", "alpha"])
    (check_alpha(args)).should be_true
    (check_beta(args)).should be_true
    (check_wip(args)).should be_false
  end

  it "'check_cnf_config' should return the value for a cnf-config argument", tags: ["args"]  do
    args = Sam::Args.new(["cnf-config=./sample-cnfs/sample-generic-cnf/cnf-testsuite.yml"])
    (check_cnf_config(args)).should eq("./sample-cnfs/sample-generic-cnf")
  end

  it "'upsert_skipped_task' should put a 0 in the results file", tags: ["task_runner"]  do
    CNFManager::Points.clean_results_yml
    resp = upsert_skipped_task("ip_addresses","✖️  FAILED: IP addresses found", Time.utc)
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    (yaml["items"].as_a.find {|x| 
      x["name"] == "ip_addresses" && 
        x["points"] == CNFManager::Points.task_points("ip_addresses", CNFManager::ResultStatus::Skipped)
    }).should be_truthy

    (yaml["items"].as_a.find {|x| x["name"] == "ip_addresses" && x["points"] == 0 }).should be_truthy
  end

  # TODO (kosstennbl) Rework this spec, shouldn't contain a real test.
  it "'single_task_runner' should accept a cnf-config argument and apply a test to that cnf", tags: ["task_runner"] do
    begin
      args = Sam::Args.new()
      config_path = "./sample-cnfs/sample-generic-cnf/cnf-testsuite.yml"
      ShellCmd.cnf_install("cnf-config=#{config_path}")
      task_response = CNFManager::Task.single_task_runner(args) do |args, config| 
        Log.info { "single_task_runner spec args #{args.inspect}" }
        white_list_container_names = config.common.white_list_container_names
        Log.info { "white_list_container_names #{white_list_container_names.inspect}" }
        violation_list = [] of String
        resource_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
          privileged_list = KubectlClient::Get.privileged_containers(all_namespaces: true).map { |container| container.dig("name") }.uniq
          resource_containers = KubectlClient::Get.resource_containers(resource["kind"],resource["name"],resource["namespace"])
          resource_containers_list = (JSON.parse(resource_containers.to_json).as_a).map { |element| element["name"] }
          # Only check the containers that are in the deployed helm chart or manifest
          (privileged_list & (resource_containers_list - white_list_container_names)).each do |x|
            violation_list << x.as_s
          end
          if violation_list.size > 0
            false
          else
            true
          end
        end
        Log.debug { "violator list: #{violation_list.flatten}" }
        emoji_security=""
        if resource_response 
          resp = upsert_passed_task("privileged_containers", "✔️  PASSED: No privileged containers", Time.utc)
        else
          resp = upsert_failed_task("privileged_containers", "✖️  FAILED: Found #{violation_list.size} privileged containers: #{violation_list.inspect}", Time.utc)
        end
        Log.info { resp }
        resp
      end
      (task_response).should eq("✔️  PASSED: No privileged containers")
    ensure
      ShellCmd.cnf_uninstall()
    end
  end

  # TODO (kosstennbl) Rework this spec, shouldn't contain a real test.
  it "'single_task_runner' should put a 1 in the results file if it has an exception", tags: ["task_runner"]  do
    CNFManager::Points.clean_results_yml
    args = Sam::Args.new()
    task_response = CNFManager::Task.single_task_runner(args) do
      raise Exception.new()
    end
    yaml = File.open("#{CNFManager::Points::Results.file}") do |file|
      YAML.parse(file)
    end
    (yaml["exit_code"]).should eq(2)
  end

  it "'logger' command line logger level setting via config.yml", tags: ["logger"]  do
    # NOTE: the config.yml file is in the root of the repo directory. 
    # By default 'loglevel' in that file is set to 'error', but 'error' is also default
    # implicit log level, so we change loglevel to 'warn' for this test.
    `sed -i 's/loglevel: error/loglevel: warn/' config.yml`
    ($?.success?).should be_true

    result = ShellCmd.run_testsuite("test", cmd_prefix: "unset LOG_LEVEL;")
    result[:status].success?.should be_true
    (/DEBUG -- CNTI: debug test/ =~ result[:output]).should be_nil
    (/INFO -- CNTI: info test/ =~ result[:output]).should be_nil
    (/WARN -- CNTI: warn test/ =~ result[:output]).should_not be_nil
    (/ERROR -- CNTI: error test/ =~ result[:output]).should_not be_nil
  ensure
    `sed -i 's/loglevel: warn/loglevel: error/' config.yml`
  end

  it "'logger' command line logger level setting works", tags: ["logger"]  do
    # Note: implicitly tests the override of config.yml if it exist in repo root
    result = ShellCmd.run_testsuite("-l debug test")
    result[:status].success?.should be_true
    (/DEBUG -- CNTI: debug test/ =~ result[:output]).should_not be_nil
  end

  it "'logger' LOGLEVEL NO underscore environment variable level setting works", tags: ["logger"]  do
    # Note: implicitly tests the override of config.yml if it exist in repo root
    result = ShellCmd.run_testsuite("test", cmd_prefix: "unset LOG_LEVEL; LOGLEVEL=DEBUG")
    result[:status].success?.should be_true
    (/DEBUG -- CNTI: debug test/ =~ result[:output]).should_not be_nil
  end

  it "'logger' LOG_LEVEL WITH underscore environment variable level setting works", tags: ["logger"]  do
    # Note: implicitly tests the override of config.yml if it exist in repo root
    result = ShellCmd.run_testsuite("test", cmd_prefix: "LOG_LEVEL=DEBUG")
    result[:status].success?.should be_true
    (/DEBUG -- CNTI: debug test/ =~ result[:output]).should_not be_nil
  end

  it "'logger' command line level setting overrides environment variable", tags: ["logger"]  do
    result = ShellCmd.run_testsuite("-l error test", cmd_prefix: "LOG_LEVEL=DEBUG")
    result[:status].success?.should be_true
    (/DEBUG -- CNTI: debug test/ =~ result[:output]).should be_nil
    (/INFO -- CNTI: info test/ =~ result[:output]).should be_nil
    (/WARN -- CNTI: warn test/ =~ result[:output]).should be_nil
    (/ERROR -- CNTI: error test/ =~ result[:output]).should_not be_nil
  end

  it "'logger' defaults to error when level set is missplled", tags: ["logger"]  do
    # Note: implicitly tests the override of config.yml if it exist in repo root
    result = ShellCmd.run_testsuite("test", cmd_prefix: "unset LOG_LEVEL; LOG_LEVEL=DEGUB")
    result[:status].success?.should be_true
    (/ERROR -- CNTI: Invalid logging level set. defaulting to ERROR/ =~ result[:output]).should_not be_nil
  end

  it "'logger' should write logs to the file when LOG_PATH is set", tags: ["logger"] do
    response_s = `LOG_PATH=spec-test-testsuite.log ./cnf-testsuite test`
    $?.success?.should be_true
    (/ERROR -- CNTI: error test/ =~ response_s).should be_nil
    File.exists?("spec-test-testsuite.log").should be_true
    (/ERROR -- CNTI: error test/ =~ File.read("spec-test-testsuite.log")).should_not be_nil
  ensure
    if File.exists?("spec-test-testsuite.log")
      File.delete("spec-test-testsuite.log")
    end
  end

  it "'#update_yml' should update the value for a key in a yml file", tags: ["logger"]  do
    begin
    update_yml("spec/fixtures/cnf-testsuite.yml", "release_name", "coredns --set worker-node='kind-control-plane'")
    yaml = File.open("spec/fixtures/cnf-testsuite.yml") do |file|
      YAML.parse(file)
    end
    (yaml["release_name"]).should eq("coredns --set worker-node='kind-control-plane'")
    ensure
      update_yml("spec/fixtures/cnf-testsuite.yml", "release_name", "coredns")
    end
  end

  describe "'download' function", tags: ["utils-download"] do
    port = 50500
    ip = "0.0.0.0"
    server = HTTP::Server.new do |ctx|
      request = ctx.request
      response = ctx.response
      case request.path
      when "/redirect"
        response.status_code = 302
        response.headers["Location"] = "http://#{ip}:#{port}/success"
        response.print("redirecting to /success")
      when "/error"
        response.status_code = 404
        response.print("not found")
      when "/auth"
        auth_header = request.headers["Authorization"]
        if auth_header && auth_header.starts_with?("Bearer ")
          response.status_code = 200
          response.print("authorized access")
        else
          response.status_code = 401
          response.print("unauthorized")
        end
      when "/success"
        response.status_code = 200
        response.print("successful response")
      end
    end

    before_all do
      server.bind_tcp(ip, port)
      spawn do
        server.listen
      end
    end

    after_all do
      server.close
    end

    it "should download file correctly" do
      tempfile = File.tempfile("test_download")
      begin
        download_file("http://#{ip}:#{port}/success", tempfile.path)
      rescue ex : Exception # Exception should not be raised
        ex.message.should be_nil
      end
      (File.read(tempfile.path) == "successful response").should be_true
    ensure
      tempfile.delete unless tempfile.nil?
    end

    it "should download file with redirection correctly" do
      tempfile = File.tempfile("test_download")
      begin
        download_file("http://#{ip}:#{port}/redirect", tempfile.path)
      rescue ex : Exception # Exception should not be raised
        ex.message.should be_nil
      end
      (File.read(tempfile.path) == "successful response").should be_true
    ensure
      tempfile.delete unless tempfile.nil?
    end

    it "should download file with bearer token authentication correctly" do
      tempfile = File.tempfile("test_download")
      headers = HTTP::Headers{"Authorization" => "Bearer valid-token123"}
      begin
        download_file("http://#{ip}:#{port}/auth", tempfile.path, headers: headers)
      rescue ex : Exception # Exception should not be raised
        ex.message.should be_nil
      end
      (File.read(tempfile.path) == "authorized access").should be_true
    ensure
      tempfile.delete unless tempfile.nil?
    end

    it "should raise when 'url' is not found" do
      tempfile = File.tempfile("test_download")
      begin
        download_file("http://non-existent/path", tempfile.path)
      rescue ex : Exception
        ex.message.should_not be_nil
      end
    ensure
      tempfile.delete unless tempfile.nil?
    end

    it "should raise when response is not 2xx" do
      tempfile = File.tempfile("test_download")
      begin
        download_file("http://#{ip}:#{port}/error", tempfile.path)
      rescue ex : Exception
        (ex.message =~ /Unsuccessful request, status code: \[404\], msg: Not Found/).should_not be_nil
      end
    ensure
      tempfile.delete unless tempfile.nil?
    end
  end
end
