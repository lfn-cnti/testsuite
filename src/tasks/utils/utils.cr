require "totem"
require "colorize"
require "./cnf_manager/cnf_manager.cr"
require "./embedded_file_manager.cr"
require "log"
require "file_utils"
require "option_parser"
require "../constants.cr"
require "semantic_version"
require "./dockerd.cr"
require "./kyverno.cr"
require "./http_helper.cr"
require "./timeouts.cr"
require "./cnf_installation/config.cr"
require "ecr"
require "http/client"

module ShellCmd
  def self.run(cmd, log_prefix = "ShellCmd.run", force_output = false, joined_output = false)
    log = Log.for(log_prefix)
    log.info { "command: #{cmd}" }
    output = IO::Memory.new
    stderr = joined_output ? output : IO::Memory.new
    status = Process.run(
      cmd,
      shell: true,
      output: output,
      error: stderr
    )
    if force_output == false
      log.debug { "output: #{output.to_s}" }
    else
      log.info { "output: #{output.to_s}" }
    end

    # Don't have to output log line if stderr is empty
    if !joined_output && stderr.to_s.size > 1
      log.info { "stderr: #{stderr.to_s}" }
    end
    {status: status, output: output.to_s, error: stderr.to_s}
  end
end

def ensure_kubeconfig!
  kubeconfig_path = File.join(ENV["HOME"], ".kube", "config")

  if ENV.has_key?("KUBECONFIG") && File.exists?(ENV["KUBECONFIG"])
    stdout_success "KUBECONFIG is already set."
  elsif File.exists?(kubeconfig_path)
    ENV["KUBECONFIG"] = kubeconfig_path
    stdout_success "KUBECONFIG is set as #{ENV["KUBECONFIG"]}."
  elsif !ENV.has_key?("KUBECONFIG")
    stdout_failure "KUBECONFIG is not set and default path #{kubeconfig_path} does not exist. Please set KUBECONFIG to an existing config file, i.e. 'export KUBECONFIG=path-to-your-kubeconfig'"
    exit 1
  else
    stdout_failure "KUBECONFIG is set to #{ENV["KUBECONFIG"]} path and it does not exist. Please set KUBECONFIG to an existing config file, i.e. 'export KUBECONFIG=path-to-your-kubeconfig'"
    exit 1
  end

  # Check if cluster is up and running with assigned KUBECONFIG variable
  begin
    KubectlClient::Get.resource("nodes")
  rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
    stdout_failure "Cluster liveness check failed: '#{ex.message}'. Check the cluster and/or KUBECONFIG environment variable."
    exit 1
  end
end

def check_cnf_config(args)
  Log.trace { "args = #{args.inspect}" }
  Log.info { "check_cnf_config args: #{args.inspect}" }
  if args.named.keys.includes? "cnf-config"
    yml_file = args.named["cnf-config"].as(String)
    cnf = File.dirname(yml_file)
    Log.debug { "all cnf: #{cnf}" }
  else
    cnf = nil
  end
  Log.info { "check_cnf_config cnf: #{cnf}" }
  cnf
end

def toggle(toggle_name)
  toggle_on = false
  if File.exists?(BASE_CONFIG)
    config = Totem.from_file BASE_CONFIG
    if config["toggles"].as_a?
      feature_flag = config["toggles"].as_a.find do |x|
        x["name"] == toggle_name
      end
      toggle_on = feature_flag["toggle_on"].as_bool if feature_flag
    end
  else
    toggle_on = false
  end
  toggle_on
end

# # check feature level e.g. --beta
# # if no feature level then feature level = ga
def check_feature_level(args)
  Log.info { "args.raw #{args.raw}" }
  case args.raw
  when .includes? "poc"
    "poc"
  when .includes? "wip"
    "wip"
  when .includes? "alpha"
    "alpha"
  when .includes? "beta"
    "beta"
  else
    "ga"
  end
end

# cncf/cnf-testsuite/issues/106
# Requesting beta tests to run will both beta and ga flagged tests
# Requesting alpha tests will run alpha, beta, and ga flagged tests
# Requesting wip tests will run wip, poc, alpha, beta, and ga flagged tests

# if the beta flag or alpha flag is true, then beta tests should be run
def check_beta
  toggle("beta") || check_alpha
end

# if the beta flag or alpha flag is true, then beta tests should be run
def check_beta(args)
  toggle("beta") || check_feature_level(args) == "beta" || check_alpha(args)
end

# if the alpha flag or wip flag is true, then alpha tests should be run
def check_alpha
  toggle("alpha") || check_wip
end

# if the alpha flag or wip flag is true, then alpha tests should be run
def check_alpha(args)
  toggle("alpha") || check_feature_level(args) == "alpha" || check_wip(args)
end

def check_wip
  toggle("wip") || toggle("poc")
end

def check_wip(args)
  toggle("wip") || check_feature_level(args) == "wip" ||
    toggle("poc") || check_feature_level(args) == "poc"
end

def check_poc
  check_wip
end

def check_containerd
  resp = KubectlClient::Get.container_runtimes
  containerd = false
  resp.each do |x|
    if (x =~ /containerd/)
      containerd = true
    end
    Log.info { "Containerd?: #{containerd}" }
  end
  containerd
end

def check_poc(args)
  check_wip(args)
end

def check_destructive
  toggle("destructive")
end

def check_destructive(args)
  Log.info { "args.raw #{args.raw}" }
  toggle("destructive") || args.raw.includes?("destructive")
end

def update_yml(yml_file, top_level_key, value)
  results = File.open("#{yml_file}") do |f|
    YAML.parse(f)
  end
  Log.debug { "update_yml results: #{results}" }
  # The last key assigned wins
  new_yaml = YAML.dump(results) + "\n#{top_level_key}: #{value}"
  parsed_new_yml = YAML.parse(new_yaml)
  Log.debug { "update_yml parsed_new_yml: #{parsed_new_yml}" }
  File.open("#{yml_file}", "w") do |f|
    YAML.dump(parsed_new_yml, f)
  end
end

def upsert_decorated_task(task, status : CNFManager::ResultStatus, message, start_time)
  tc_emoji = CNFManager::Points.emoji_by_task(task)
  cat_emoji = CNFManager::Points.task_emoji_by_task(task)
  case status.to_basic
  when CNFManager::ResultStatus::Passed
    upsert_passed_task(task, "✔️  #{cat_emoji}PASSED: [#{task}] #{message} #{tc_emoji}", start_time)
  when CNFManager::ResultStatus::Failed
    upsert_failed_task(task, "✖️  #{cat_emoji}FAILED: [#{task}] #{message} #{tc_emoji}", start_time)
  when CNFManager::ResultStatus::Skipped
    upsert_skipped_task(task, "⏭️  #{cat_emoji}SKIPPED: [#{task}] #{message} #{tc_emoji}", start_time)
  when CNFManager::ResultStatus::NA
    upsert_na_task(task, "⏭️  #{cat_emoji}N/A: [#{task}] #{message} #{tc_emoji}", start_time)
  when CNFManager::ResultStatus::Error
    upsert_error_task(task, "💥  #{cat_emoji}ERROR: [#{task}] #{message}", start_time)
  end
end

def upsert_failed_task(task, message, start_time)
  CNFManager::Points.upsert_task(task, FAILED, CNFManager::Points.task_points(task, CNFManager::ResultStatus::Failed), start_time)
  stdout_failure message
  message
end

def upsert_passed_task(task, message, start_time)
  CNFManager::Points.upsert_task(task, PASSED, CNFManager::Points.task_points(task, CNFManager::ResultStatus::Passed), start_time)
  stdout_success message
  message
end

def upsert_skipped_task(task, message, start_time)
  CNFManager::Points.upsert_task(task, SKIPPED, CNFManager::Points.task_points(task, CNFManager::ResultStatus::Skipped), start_time)
  stdout_warning message
  message
end

def upsert_na_task(task, message, start_time)
  CNFManager::Points.upsert_task(task, NA, CNFManager::Points.task_points(task, CNFManager::ResultStatus::NA), start_time)
  stdout_warning message
  message
end

def upsert_error_task(task, message, start_time)
  CNFManager::Points.upsert_task(task, ERROR, CNFManager::Points.task_points(task, CNFManager::ResultStatus::Error), start_time)
  stdout_error message
  message
end

def upsert_dynamic_task(task, status : CNFManager::ResultStatus, message, start_time)
  CNFManager::Points.upsert_task(task, status.to_s.downcase, CNFManager::Points.task_points(task, status), start_time)
  case status.to_s.downcase
  when /pass/
    stdout_success message
  when /fail/
    stdout_failure message
    message
  else
    stdout_warning message
  end
  message
end

def testsuite_resources_dir
  default_dir = "#{ENV["HOME"]}/.cnf-testsuite"
  testsuite_dir = ENV.fetch("CNF_TESTSUITE_DIR", default_dir)
  FileUtils.mkdir_p(testsuite_dir) if !Dir.exists?(testsuite_dir)
  return testsuite_dir
end

def tools_path
  value = "#{testsuite_resources_dir}/tools"
  FileUtils.mkdir_p(value) if !Dir.exists?(value)
  value
end

def stdout_info(msg, same_line = false)
  if same_line
    msg = "#{"\e[1A\e[K"}#{msg}"
  end
  puts msg
end

# \e[1A\e[K is a sequence that allows to clear current line and place cursor at its beginning
def stdout_colored(msg, color, same_line = false)
  if same_line
    msg = "#{"\e[1A\e[K"}#{msg}"
  end
  puts msg.colorize(color)
end

def stdout_success(msg, same_line = false)
  stdout_colored(msg, :green, same_line)
end

def stdout_warning(msg, same_line = false)
  stdout_colored(msg, :yellow, same_line)
end

def stdout_failure(msg, same_line = false)
  stdout_colored(msg, :red, same_line)
end

def stdout_error(msg, same_line = false)
  stdout_colored(msg, Colorize::Color256.new(208), same_line)
end

def stdout_score(test_name)
  stdout_score(test_name, test_name)
end

def stdout_score(test_name : String, full_name)
  stdout_score([test_name], full_name)
end

def stdout_score(test_names : Array(String), full_name)
  total = CNFManager::Points.total_points(test_names)
  max_points = CNFManager::Points.total_max_points(test_names)
  total_passed = CNFManager::Points.total_passed(test_names)
  max_passed = CNFManager::Points.total_max_passed(test_names)
  essential_total_passed = CNFManager::Points.total_passed("essential")
  essential_max_passed = CNFManager::Points.total_max_passed("essential")

  pretty_test_name = full_name.split(/:|_/).map(&.capitalize).join(" ")
  test_log_msg =
    <<-STRING
#{pretty_test_name} results: #{total_passed} of #{max_passed} tests passed

STRING
  update_yml("#{CNFManager::Points::Results.file}", "points", total)
  update_yml("#{CNFManager::Points::Results.file}", "maximum_points", max_points)

  if total > 0
    stdout_success test_log_msg
  else
    stdout_failure test_log_msg
  end
end

# this method extracts a string value from a config section if it exists
# if the value is an integer it will be converted to a string before extraction
def optional_key_as_string(totem_config, key_name)
  "#{totem_config[key_name]? && (totem_config[key_name].as_s? || totem_config[key_name].as_i?)}"
end

# compare 2 SemVer strings and return true if v1 is less than v2
def version_less_than(v1str, v2str)
  # k3s verisons look like this (valid semantic version): 1.23.6+k3s1
  #
  # microk8s verisons look like this (invalid semantic version): 1.20+.0
  #
  # microk8s version strings are bad input to the semantic version parser.
  # To allow microk8s, we strip the plus sign from the minor version.
  # The below code block performs that cleanup.

  v1str = v1str.split(".").map { |i| i.ends_with?("+") ? i.gsub("+", "") : i }
  v1str = v1str.join(".")
  v2str = v2str.split(".").map { |i| i.ends_with?("+") ? i.gsub("+", "") : i }
  v2str = v2str.join(".")

  v1 = SemanticVersion.parse(v1str)
  v2 = SemanticVersion.parse(v2str)
  less_than = (v1 <=> v2) == -1
  Log.debug { "version_less_than: #{v1} < #{v2}: #{less_than}" }
  less_than
end

def with_kubeconfig(kube_config : String, &)
  last_kube_config = ENV["KUBECONFIG"]
  ENV["KUBECONFIG"] = kube_config
  result = yield
  ENV["KUBECONFIG"] = last_kube_config
  result
end

def find(directory : String, wildcard : String)
  Log.debug { "find command: find #{directory} -name #{wildcard}" }
  status = Process.run("find #{directory} -name #{wildcard}",
    shell: true,
    output: output = IO::Memory.new,
    error: stderr = IO::Memory.new)
  Log.debug { "find output: #{output.to_s}" }
  Log.warn { "find stderr: #{stderr.to_s}" } unless stderr.to_s.empty?
  found_files = output.to_s.split("\n").select { |x| x.empty? == false }

  found_files
end

def download(url : String, output_path : String,
                  redirect_limit : Int = 5, headers : HTTP::Headers? = nil)
  raise "Too many redirects" if redirect_limit == 0

  response = HTTP::Client.get(url, headers: headers)
  if response.status_code >= 300 && response.status_code < 400
    new_location = response.headers["Location"]
    raise "Status code 3xx, but redirect location missing" unless new_location
    return download(new_location, output_path, redirect_limit - 1, headers)
  end

  unless response.success?
    raise "Unsuccessful request, status code: [#{response.status_code}], msg: #{response.status_message}"
  end
  File.write(output_path, response.body.to_s)
end
