# coding: utf-8
require "sam"
require "colorize"
require "../utils/utils.cr"
require "retriable"
require "../../modules/k8s_kernel_introspection"

namespace "platform" do
  desc "The CNF test suite checks to see if the Platform has Observability support."
  task "observability", ["kube_state_metrics", "node_exporter", "prometheus_adapter", "metrics_server"] do |t, args|
    Log.debug { "observability" }
    Log.trace { "observability args.raw: #{args.raw}" }
    Log.trace { "observability args.named: #{args.named}" }
    stdout_score("platform:observability")
  end

  desc "Does the Platform have Kube State Metrics installed"
  task "kube_state_metrics", ["install_cluster_tools"] do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      unless check_poc(args)
        next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Kube State Metrics not in poc mode")
      end
      Log.info { "Running POC: kube_state_metrics" }
      found = KernelIntrospection::K8s.find_first_process(CloudNativeIntrospection::STATE_METRICS_PROCESS)
      Log.info { "Found Pod: #{found}" }

      if found
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your platform is using the release for kube state metrics")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Your platform does not have kube state metrics installed")
      end
    end
  end

  desc "Does the Platform have a Node Exporter installed"
  task "node_exporter", ["install_cluster_tools"] do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      unless check_poc(args)
        next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "node exporter not in poc mode")
      end
      Log.info { "Running POC: node_exporter" }
      found = KernelIntrospection::K8s.find_first_process(CloudNativeIntrospection::NODE_EXPORTER)
      Log.info { "Found Process: #{found}" }
      if found
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your platform is using the node exporter")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Your platform does not have the node exporter installed")
      end
    end
  end


  desc "Does the Platform have the prometheus adapter installed"
  task "prometheus_adapter", ["install_cluster_tools"] do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      unless check_poc(args)
        next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "prometheus adapter not in poc mode")
      end
      Log.info { "Running POC: prometheus_adapter" }
      found = KernelIntrospection::K8s.find_first_process(CloudNativeIntrospection::PROMETHEUS_ADAPTER)
      Log.info { "Found Process: #{found}" }

      if found
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your platform is using the prometheus adapter")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Your platform does not have the prometheus adapter installed")
      end
    end
  end

  desc "Does the Platform have the K8s Metrics Server installed"
  task "metrics_server", ["install_cluster_tools"] do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
      unless check_poc(args)
        next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Metrics server not in poc mode")
      end
      Log.info { "Running POC: metrics_server" }
      found = KernelIntrospection::K8s.find_first_process(CloudNativeIntrospection::METRICS_SERVER)
      if found
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your platform is using the metrics server")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Your platform does not have the metrics server installed")
      end
    end
  end
end

def named_sha_list(resp_json)
  Log.debug { "sha_list resp_json: #{resp_json}" }
  parsed_json = JSON.parse(resp_json)
  Log.debug { "sha list parsed json: #{parsed_json}" }
  #if tags then this is a quay repository, otherwise assume docker hub repository
  if parsed_json["tags"]?
    parsed_json["tags"].not_nil!.as_a.reduce([] of Hash(String, String)) do |acc, i|
      acc << {"name" => i["name"].not_nil!.as_s, "manifest_digest" => i["manifest_digest"].not_nil!.as_s}
    end
  else
    parsed_json["results"].not_nil!.as_a.reduce([] of Hash(String, String)) do |acc, i|
      # always use amd64
      amd64image = i["images"].as_a.find{|x| x["architecture"].as_s == "amd64"}
      Log.debug { "amd64image: #{amd64image}" }
      if amd64image && amd64image["digest"]?
        acc << {"name" => i["name"].not_nil!.as_s, "manifest_digest" => amd64image["digest"].not_nil!.as_s}
      else
        Log.error { "amd64 image not found in #{i["images"]}" }
        acc
      end
    end
  end
end
