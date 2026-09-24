# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../../modules/kernel_introspection"
require "../../modules/k8s_kernel_introspection"
require "../utils/utils.cr"

desc "In order to maintain, debug, and have insight into a protected environment, its infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends itself to metrics, tracing, and logging."
category_task "observability", ["log_output", "prometheus_traffic", "open_metrics", "routed_logs", "tracing"],
  title: "Observability and Diagnostics"

desc "Check if the CNF outputs logs to stdout or stderr"
scored_task "log_output",
  type: CNFManager::TestType::Essential,
  emoji: "📶☠️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Pods whose logs could not be read (not scheduled, container still
    # creating, ...) are reported, never judged.
    unreadable = [] of String
    logged_resources = [] of String
    judged_any = false

    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      resource_yaml = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      pods = KubectlClient::Get.pods_by_resource_labels(resource_yaml, resource[:namespace])

      # Every pod of the resource is read - `kubectl logs <kind>/<name>` would
      # sample just one - and the resource logs if any of them does.
      logging = [] of String
      quiet = [] of String
      pods.each do |pod|
        pod_name = pod.dig("metadata", "name").as_s
        # A pod that is not running has nothing to say yet; kubectl prints no
        # logs and no error for one that was never scheduled.
        phase = pod.dig?("status", "phase").try(&.as_s) || "Unknown"
        unless phase == "Running"
          unreadable << "#{resource[:kind]}/#{resource[:name]} pod #{pod_name}: pod is #{phase}"
          next
        end
        begin
          log_result = KubectlClient::Utils.logs("pod/#{pod_name}", namespace: resource[:namespace], options: "--all-containers --tail=5 --prefix=true")
          Log.for(t.name).info { "#{pod_name} log lines: #{log_result[:output]}" }
          (log_result[:output].strip.empty? ? quiet : logging) << pod_name
        rescue ex : KubectlClient::ShellCMD::NetworkError
          raise ex
        rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
          unreadable << "#{resource[:kind]}/#{resource[:name]} pod #{pod_name}: #{ex.message.to_s.lines.first?.to_s.strip}"
        end
      end

      # Nothing readable: this resource is not judged.
      next true if logging.empty? && quiet.empty?
      judged_any = true

      if logging.empty?
        quiet.each { |pod_name| result.add_impacted_resource("Pod", pod_name, resource[:namespace], reason: "no log output on stdout/stderr") }
        false
      else
        logged_resources << "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: logs from #{logging.join(", ")}"
        true
      end
    end

    unreadable.each { |line| result.append_description("Logs could not be read: #{line}") }
    if !judged_any
      result.skipped("Log output not checked: no pod's logs could be read")
    elsif task_response
      logged_resources.each { |line| result.append_description(line) }
      result.passed("Resources output logs to stdout and stderr")
    else
      result.failed("Resources do not output logs to stdout and stderr")
    end
  end
end

desc "Does the CNF emit prometheus traffic"
scored_task "prometheus_traffic",
  type: CNFManager::TestType::Bonus,
  emoji: "📶☠️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    server = Prometheus.find_server
    if server.nil? || server[:url].nil?
      result.append_description(Prometheus.describe_missing(server))
      result.na("Prometheus server not found: nothing scrapes the CNF in this cluster")
      next
    end
    result.append_description(Prometheus.describe(server))
    targets = server[:targets]

    # A workload sends Prometheus traffic when one of the active targets
    # scrapes one of its pods; each one no target scrapes is a finding.
    unscraped = 0
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      live = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      ips = Prometheus.pod_ips(KubectlClient::Get.pods_by_resource_labels(live, resource[:namespace]))
      label = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}"
      matched = Prometheus.targets_for_ips(ips, targets)
      if matched.empty?
        unscraped += 1
        where = ips.empty? ? "its pods have no IP yet" : "pod IPs #{ips.join(", ")}"
        result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace],
          reason: "none of Prometheus's #{targets.size} active targets scrapes its pods (#{where})")
        false
      else
        matched.each do |target|
          error = target[:last_error].empty? ? "" : ", last error: #{target[:last_error]}"
          result.append_description("#{label}: scraped at #{target[:scrape_url]} (health #{target[:health]}#{error})")
        end
        true
      end
    end

    if task_response
      result.passed("Your cnf is sending prometheus traffic")
    else
      result.append_remediation("Expose a /metrics endpoint on each workload and register it with Prometheus: annotate the pods (prometheus.io/scrape, prometheus.io/port, prometheus.io/path) for annotation-based discovery, or add a ServiceMonitor/PodMonitor for the Prometheus Operator.")
      result.failed("Your cnf is not sending prometheus traffic: #{unscraped} workload(s) not scraped")
    end
  end
end

desc "Does the CNF emit prometheus open metric compatible traffic"
scored_task "open_metrics",
  type: CNFManager::TestType::Bonus,
  emoji: "📶☠️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # The endpoints Prometheus scrapes on the CNF's pods are fetched and run
    # through the OpenMetrics validator, each one reported by URL; nothing is
    # passed on through a ConfigMap from prometheus_traffic any more.
    server = Prometheus.find_server
    if server.nil? || server[:url].nil?
      result.append_description(Prometheus.describe_missing(server))
      result.na("Prometheus server not found: nothing scrapes the CNF in this cluster")
      next
    end
    result.append_description(Prometheus.describe(server))

    validated = 0
    invalid = 0
    CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      live = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      ips = Prometheus.pod_ips(KubectlClient::Get.pods_by_resource_labels(live, resource[:namespace]))
      label = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}"
      matched = Prometheus.targets_for_ips(ips, server[:targets])
      if matched.empty?
        result.append_description("#{label}: no Prometheus target scrapes its pods, nothing to validate")
        next true
      end
      matched.all? do |target|
        validated += 1
        resp = Prometheus.open_metric_validator(target[:scrape_url])
        response = "#{resp[:output]}\n#{resp[:error]}".strip
        if resp[:status].success?
          result.append_description("#{label}: #{target[:scrape_url]} is OpenMetrics compatible")
          true
        else
          invalid += 1
          result.append_description("#{label}: #{target[:scrape_url]} failed validation: #{response}")
          result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace],
            reason: "metrics at #{target[:scrape_url]} are not OpenMetrics compatible: #{response.lines.first?.to_s.strip}")
          false
        end
      end
    end

    if validated == 0
      result.skipped("No metrics endpoint of the CNF is scraped by Prometheus, nothing to validate")
    elsif invalid == 0
      result.passed("Your cnf's metrics traffic is OpenMetrics compatible")
    else
      result.append_remediation("Serve the metrics in the OpenMetrics text format (https://github.com/OpenObservability/OpenMetrics/blob/main/specification/OpenMetrics.md): content type application/openmetrics-text, one TYPE and HELP per family, a final # EOF line; the validator's message names the first violation.")
      result.failed("Your cnf's metrics traffic is not OpenMetrics compatible")
    end
  end
end

desc "Are the CNF's logs captured by a logging system"
scored_task "routed_logs",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:install_cluster_tools"],
  emoji: "📶☠️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    fluent_pods = FluentManager.find_active_match_pods
    unless fluent_pods
      result.na("Fluentd or FluentBit not configured: nothing routes the CNF's logs in this cluster")
      next
    end

    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource_name, _, _|
      resource = KubectlClient::Get.resource(resource_name[:kind], resource_name[:name], resource_name[:namespace])
      pods = KubectlClient::Get.pods_by_resource_labels(resource, namespace: resource_name[:namespace])

      pods.all? do |pod|
        pod_name = pod.dig("metadata", "name").as_s
        if FluentManager.pod_tailed?(pod_name, fluent_pods)
          true
        else
          result.add_impacted_resource(resource_name[:kind], resource_name[:name], resource_name[:namespace], pod: pod_name, reason: "logs are not being captured")
          false
        end
      end
    end

    if task_response
      result.passed("Your CNF's logs are being captured")
    else
      result.failed("Your CNF's logs are not being captured")
    end
  end
end

desc "Does the CNF install use tracing?"
scored_task "tracing",
  type: CNFManager::TestType::Bonus,
  emoji: "⎈🚀" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    unless JaegerManager.available?
      result.na("Jaeger not configured: nothing collects the CNF's traces in this cluster")
      next
    end

    # Pod names Jaeger has seen traces from, per emitting service: in-cluster
    # jaeger clients report the pod name as the "hostname" process tag.
    services_by_hostname = Hash(String, Set(String)).new
    JaegerManager.services.each do |service|
      JaegerManager.trace_hostnames(service).each do |hostname|
        (services_by_hostname[hostname] ||= Set(String).new) << service
      end
    end
    Log.for(t.name).info { "hostnames with traces: #{services_by_hostname.keys}" }

    untraced = [] of NamedTuple(kind: String, name: String, namespace: String)
    traced_any = false
    uninspected = 0
    CNFManager.cnf_workload_resources(args, config) do |resource|
      kind = resource.dig?("kind").try(&.as_s?)
      name = resource.dig?("metadata", "name").try(&.as_s?)
      next unless kind && name
      next unless KubectlClient::WORKLOAD_RESOURCES.values.includes?(kind)
      namespace = resource.dig?("metadata", "namespace").try(&.as_s?) || CLUSTER_DEFAULT_NAMESPACE
      resource_yaml = KubectlClient::Get.resource(kind, name, namespace)
      pods = KubectlClient::Get.pods_by_resource_labels(resource_yaml, namespace)
      pod_names = pods.compact_map { |pod| pod.dig?("metadata", "name").try(&.as_s?) }
      traced_pods = pod_names.select { |pod_name| services_by_hostname.has_key?(pod_name) }

      if traced_pods.empty?
        untraced << {kind: kind, name: name, namespace: namespace}
      else
        traced_any = true
        traced_pods.each do |pod_name|
          result.append_description("#{kind}/#{name}: traces in Jaeger from #{pod_name} (service #{services_by_hostname[pod_name].join(", ")})")
        end
      end
    rescue ex : KubectlClient::ShellCMD::NetworkError
      raise ex
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      # A resource that cannot be inspected is reported, not judged.
      uninspected += 1
      result.append_description("#{kind}/#{name}: could not be inspected: #{ex.message.to_s.lines.first?.to_s.strip}")
    end

    if traced_any
      result.passed("Tracing used")
    elsif untraced.empty? && uninspected > 0
      result.skipped("Tracing not checked: no workload could be inspected")
    else
      untraced.each do |info|
        result.add_impacted_resource(info[:kind], info[:name], info[:namespace], reason: "no traces in Jaeger from any of its pods")
      end
      result.failed("Tracing not used")
    end
  end
end
