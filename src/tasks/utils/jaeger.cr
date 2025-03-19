require "../../modules/cluster_tools"

module JaegerManager
  # JAEGER_PORT = "14271" # agent port
  JAEGER_PORT = "14269" # collector port
  def self.match()
    ClusterTools.local_match_by_image_name("jaegertracing/jaeger-collector")
  end
  def self.uninstall
    Log.debug { "uninstall_jaeger" } 
    Helm.uninstall("jaeger", "jaeger")
  end

  def self.install
    Log.info {"Installing Jaeger daemonset "}
    Helm.helm_repo_add("jaegertracing","https://jaegertracing.github.io/helm-charts")
    CNFManager.ensure_namespace_exists!("jaeger")
    Helm.install("jaeger", "jaegertracing/jaeger", namespace: "jaeger", values: "--set cassandra.config.cluster_size=1 --set cassandra.config.seed_size=1")
    KubectlClient::Wait.resource_wait_for_install("Deployment", "jaeger-collector", 300, namespace: "jaeger")
    KubectlClient::Wait.resource_wait_for_install("Deployment", "jaeger-query", 300, namespace: "jaeger")
    KubectlClient::Wait.resource_wait_for_install("Daemonset", "jaeger-agent", 300, namespace: "jaeger")
  end

  def self.node_for_cnf(resource_name)
    KubectlClient.nodes_by_resource(resource)
  end


  def self.jaeger_pods(nodes)
    match = ClusterTools.local_match_by_image_name("jaegertracing/jaeger-collector", nodes)
    KubectlClient::Get.pods_by_digest_and_nodes(match[:digest], nodes)
  end

  def self.jaeger_metrics_by_pods(jaeger_pods)
    #todo cluster tools curl call
    Log.info { "jaeger_metrics_by_pods"}
    metrics = jaeger_pods.map do |pod|
      Log.debug { "jaeger_metrics_by_pods pod: #{pod}"}
      pod_ips = pod.dig?("status", "podIPs")
      Log.debug { "pod_ips: #{pod_ips}"}
      if pod_ips
        ip_metrics = pod_ips.as_a.map do |ip|
          Log.debug{ "checking: against #{ip.dig("ip").as_s}"}
          msg = metrics_by_pod(ip.dig("ip").as_s)
          Log.debug{ "msg #{msg}"}
          msg
        end
      else
        ip_metrics = ""
      end
      Log.debug { "jaeger_metrics_by_pods ip_metrics: #{ip_metrics}"}
      ip_metrics
    end
    Log.debug { "jaeger_metrics_by_pods metrics: #{metrics}"}
    metrics.flatten
  end

  #todo move to prometheus module
  def self.metrics_by_pod(url)
    Log.info { "ClusterTools jaeger metrics" }
    #todo debug this (wrong) ip
    cli = %(curl http://#{url}:#{JAEGER_PORT}/metrics)
    resp = ClusterTools.exec(cli)
    Log.info { "jaeger metrics resp: #{resp[:output]}"}
    resp[:output]
  end

  def self.connected_clients_total
    nodes = KubectlClient::Get.resource("nodes")
    pods = jaeger_pods(nodes["items"].as_a)
    metrics = jaeger_metrics_by_pods(pods)
    total_clients = metrics.reduce(0) do |acc, metric|
      connected_clients = metric.match(/jaeger_agent_client_stats_connected_clients \K[0-9]{1,20}/)
      clients = connected_clients[0] if connected_clients
      if clients
        acc + clients.to_i
      else
        acc
      end

    end
    Log.info { "total clients for all pods: #{total_clients}" }
    total_clients
  end

  def self.unique_services_total
    nodes = KubectlClient::Get.resource("nodes")
    pods = jaeger_pods(nodes["items"].as_a)
    metrics = jaeger_metrics_by_pods(pods)
    total_count = metrics.reduce(0) do |acc, metric|
      unique_services = metric.match(/jaeger_agent_client_stats_connected_clients \K[0-9]{1,20}/)
      unique_services = metric.split("/n").reduce(0) do |acc, f|
        c = (f =~ /jaeger_collector_spans_saved_by_svc_total{debug=".*",result=".*",svc="(?!other-services).*}/)
        if c
          acc + 1
        else
          acc
        end
      end
      if unique_services 
        acc + unique_services 
      else
        acc
      end
    end
    Log.info { "total unique services for all pods: #{total_count}" }
    total_count
  end
end

