# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "kernel_introspection"
require "k8s_kernel_introspection"
require "../utils/utils.cr"

desc "In order to maintain, debug, and have insight into a protected environment, its infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends itself to metrics, tracing, and logging."
task "observability", ["log_output", "prometheus_traffic", "open_metrics", "routed_logs", "tracing"] do |_, args|
  stdout_score("observability", "Observability and Diagnostics")
  case "#{ARGV.join(" ")}" 
  when /observability/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end

desc "Check if the CNF outputs logs to stdout or stderr"
task "log_output" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args,config|
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      test_passed = false
      case resource["kind"].downcase
      when .in?(WORKLOAD_RESOURCE_KIND_NAMES)
        result = KubectlClient::Utils.logs("#{resource["kind"]}/#{resource["name"]}", namespace: resource[:namespace], options: "--all-containers --tail=5 --prefix=true")
        Log.for("Log lines").info { result[:output] }
        if result[:output].size > 0
          test_passed = true
        end
      end
      test_passed
    end
    if task_response 
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Resources output logs to stdout and stderr")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Resources do not output logs to stdout and stderr")
    end
  end
end

desc "Does the CNF emit prometheus traffic"
task "prometheus_traffic" do |t, args|
  task_response = CNFManager::Task.task_runner(args, task: t) do |args, config|

    do_this_on_each_retry = ->(ex : Exception, attempt : Int32, elapsed_time : Time::Span, next_interval : Time::Span) do
      Log.info { "#{ex.class}: '#{ex.message}' - #{attempt} attempt in #{elapsed_time} seconds and #{next_interval} seconds until the next try."}
    end

    matching_processes = KernelIntrospection::K8s.find_matching_processes(CloudNativeIntrospection::PROMETHEUS_PROCESS)
    Log.for("prometheus_traffic:process_search").info { "Found #{matching_processes.size} matching processes for prometheus" }

    prom_json : JSON::Any | Nil = nil
    matching_processes.map do |process_info|
      Log.for("prometheus_traffic:service_for_pod").info { "Checking process: #{process_info[:pid]}"}
      service = KubectlClient::Get.service_by_pod(process_info[:pod])
      next if service.nil?
      service_name = service.dig("metadata", "name")
      service_namespace = "default"
      if service.dig?("metadata", "namespace")
        service_namespace = service.dig("metadata", "namespace")
      end

      Log.for("prometheus_traffic:service_url").info { "Checking ports on service_name: #{service_name}"}
      service_ports = service.dig("spec", "ports")
      port_result = service_ports.as_a.map do |service_port|
        port = service_port.dig("port")
        protocol = service_port.dig("protocol")
        next if protocol != "TCP"
        protocol = port == 443 ? "https" : "http"
        service_url = "#{protocol}://#{service_name}.#{service_namespace}.svc.cluster.local:#{port}"
        begin
          prom_api_resp = ClusterTools.exec("curl #{service_url}/api/v1/targets?state=active")
          Log.debug { "prom_api_resp: #{prom_api_resp}"}
          prom_json = JSON.parse(prom_api_resp[:output])
          Log.for("prometheus_traffic:service_url_pass").info { "Prometheus service_url: #{service_url}" }
          break
        rescue ex
          Log.for("prometheus_traffic:service_url_fail").info { "Failed prometheus service_url: #{service_url}" }
        end
      end
    end

    if !prom_json.nil?
      matched_target = false
      active_targets = prom_json.dig("data", "activeTargets")
      Log.debug { "active_targets: #{active_targets}"}
      prom_target_urls = active_targets.as_a.reduce([] of String) do |acc, target|
        acc << target.dig("scrapeUrl").as_s
        acc << target.dig("globalUrl").as_s
      end
      Log.info { "prom_target_urls: #{prom_target_urls}"}
      prom_cnf_match = CNFManager.workload_resource_test(args, config) do |resource_name, container, initialized|
        ip_match = false
        resource = KubectlClient::Get.resource(resource_name[:kind], resource_name[:name], resource_name[:namespace])
        pods = KubectlClient::Get.pods_by_resource_labels(resource, resource_name[:namespace])
        pods.each do |pod|
          pod_ips = pod.dig("status", "podIPs")
          Log.info { "pod_ips: #{pod_ips}"}
          pod_ips.as_a.each do |ip|
            prom_target_urls.each do |url|
              Log.info { "checking: #{url} against #{ip.dig("ip").as_s}"}
              if url.includes?(ip.dig("ip").as_s)
                msg = Prometheus.open_metric_validator(url)
                # Immutable config maps are only supported in Kubernetes 1.19+
                immutable_configmap = true

                if version_less_than(KubectlClient.server_version, "1.19.0")
                  immutable_configmap = false
                end
                if msg[:status].success?
                  metrics_config_map = Prometheus::OpenMetricConfigMapTemplate.new(
                    "cnf-testsuite-open-metrics",
                    true,
                    "",
                    immutable_configmap
                  ).to_s
                else
                  Log.info { "Openmetrics failure reason: #{msg[:output]}"}
                  metrics_config_map = Prometheus::OpenMetricConfigMapTemplate.new(
                    "cnf-testsuite-open-metrics",
                    false,
                    msg[:output],
                    immutable_configmap
                  ).to_s
                end

                Log.debug { "metrics_config_map : #{metrics_config_map}" }
                configmap_path = "#{CNF_TEMP_FILES_DIR}/metrics_configmap.yml"
                File.write(configmap_path, "#{metrics_config_map}")
                begin KubectlClient::Delete.file(configmap_path) rescue KubectlClient::ShellCMD::NotFoundError end
                KubectlClient::Apply.file(configmap_path)
                ip_match = true
              end
            end
          end
        end
        ip_match 
      end

      # todo 1) check if scrape_url is ip address that directly matches cnf
      # todo 2) check if scrape_url is ip address that maps to service
      #  -- get ip address for the service
      #  -- match ip address to cnf ip addresses
      # todo check if scrape_url is not an ip, assume it is a service, then do task (2)
      if prom_cnf_match
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your cnf is sending prometheus traffic")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Your cnf is not sending prometheus traffic")
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Prometheus server not found")
    end
  end
end

desc "Does the CNF emit prometheus open metric compatible traffic"
task "open_metrics", ["prometheus_traffic"] do |t, args|
  task_response = CNFManager::Task.task_runner(args, task: t) do |args, config|
    begin
      configmap = KubectlClient::Get.resource("configmap", "cnf-testsuite-open-metrics")
    rescue KubectlClient::ShellCMD::NotFoundError
    end

    if !configmap.nil? && configmap != EMPTY_JSON
      open_metrics_validated = configmap["data"].as_h["open_metrics_validated"].as_s

      if open_metrics_validated == "true"
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your cnf's metrics traffic is OpenMetrics compatible")
      else
        open_metrics_response = configmap["data"].as_h["open_metrics_response"].as_s
        puts "OpenMetrics Failed: #{open_metrics_response}".colorize(:red)
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Your cnf's metrics traffic is not OpenMetrics compatible")
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Prometheus traffic not configured")
    end
  end
end

desc "Are the CNF's logs captured by a logging system"
task "routed_logs", ["install_cluster_tools"] do |t, args|
  task_response = CNFManager::Task.task_runner(args, task: t) do |args, config|
    fluent_pods = FluentManager.find_active_match_pods()
    unless fluent_pods
      next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Fluentd or FluentBit not configured")
    end

    all_pods_logged = true
    CNFManager.workload_resource_test(args, config) do |resource_name, container, initialized|
      resource = KubectlClient::Get.resource(resource_name[:kind], resource_name[:name], resource_name[:namespace])
      pods = KubectlClient::Get.pods_by_resource_labels(resource, namespace: resource_name[:namespace])
  
      pods.each do |pod|
        pod_name = pod.dig("metadata", "name").as_s
        unless FluentManager.pod_tailed?(pod_name, fluent_pods)
          Log.info { "Pod #{pod_name} logs are not being captured "}
          all_pods_logged = false
          break
        end
      end

      break unless all_pods_logged
    end
    
    if all_pods_logged
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your CNF's logs are being captured")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Your CNF's logs are not being captured")
    end
  end
end

desc "Does the CNF install use tracing?"
task "tracing" do |t, args|
  Log.for(t.name).info { "Running test" }
  Log.for(t.name).info { "tracing args: #{args.inspect}" }

  cnf_config_ok = check_cnf_config(args) || CNFManager.cnf_installed?
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    if cnf_config_ok
      match = JaegerManager.match()
      Log.info { "jaeger match: #{match}" }
      if match[:found]
        # (kosstennbl) TODO: Redesign tracing test, preferably without usage of installation configmaps. More info in issue #2153
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "tracing test is disabled, check #2153")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Jaeger not configured")
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "No cnf_testsuite.yml found! Did you run the \"cnf_install\" task?")
    end
  end
end
