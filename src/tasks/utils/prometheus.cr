require "../../modules/kernel_introspection"
require "../../modules/k8s_kernel_introspection"
require "./cloud_native_introspection.cr"

# Finding the Prometheus server in the cluster and what it scrapes; used by
# prometheus_traffic and open_metrics, which report what was probed (#2600).
module Prometheus
  alias Target = NamedTuple(scrape_url: String, global_url: String, health: String, last_error: String)
  # The server found: the pod running a prometheus process, the Service
  # selecting it, every URL probed, and, when one answered, that URL and
  # the active targets it reported.
  alias Server = NamedTuple(pod: String, namespace: String, service: String?, probed: Array(String), url: String?, targets: Array(Target))

  TARGETS_API = "/api/v1/targets?state=active"

  def self.find_server : Server?
    processes = KernelIntrospection::K8s.find_matching_processes(CloudNativeIntrospection::PROMETHEUS_PROCESS)
    Log.for("prometheus").info { "#{processes.size} process(es) matching #{CloudNativeIntrospection::PROMETHEUS_PROCESS}" }
    return nil if processes.empty?

    probed = [] of String
    last : Server? = nil
    processes.each do |info|
      pod_name = info[:pod].dig("metadata", "name").as_s
      pod_namespace = info[:pod].dig?("metadata", "namespace").try(&.as_s?) || "default"
      service = KubectlClient::Get.service_by_pod(info[:pod])
      if service.nil?
        last = {pod: pod_name, namespace: pod_namespace, service: nil, probed: probed, url: nil, targets: [] of Target}
        next
      end
      service_name = service.dig("metadata", "name").as_s
      service_namespace = service.dig?("metadata", "namespace").try(&.as_s?) || "default"
      last = {pod: pod_name, namespace: pod_namespace, service: service_name, probed: probed, url: nil, targets: [] of Target}
      (service.dig?("spec", "ports").try(&.as_a?) || [] of JSON::Any).each do |service_port|
        next if service_port["protocol"]? && service_port["protocol"] != "TCP"
        port = service_port["port"]
        url = "#{port == 443 ? "https" : "http"}://#{service_name}.#{service_namespace}.svc.cluster.local:#{port}"
        probed << url
        targets = active_targets(url)
        next if targets.nil?
        return {pod: pod_name, namespace: pod_namespace, service: service_name, probed: probed, url: url, targets: targets}
      end
    end
    last
  end

  # The active targets Prometheus reports at this base URL; nil when the
  # targets API does not answer there.
  def self.active_targets(url : String) : Array(Target)?
    resp = ClusterTools.exec("curl -sS --max-time 10 #{url}#{TARGETS_API}")
    json = JSON.parse(resp[:output])
    return nil unless json["status"]? == "success"
    (json.dig?("data", "activeTargets").try(&.as_a?) || [] of JSON::Any).map do |t|
      {scrape_url: t["scrapeUrl"]?.try(&.as_s?) || "", global_url: t["globalUrl"]?.try(&.as_s?) || "",
       health: t["health"]?.try(&.as_s?) || "unknown", last_error: t["lastError"]?.try(&.as_s?) || ""}
    end
  rescue JSON::ParseException | KubectlClient::ShellCMD::K8sClientCMDException
    nil
  end

  # The targets whose URL is on one of these pod IPs.
  def self.targets_for_ips(ips : Array(String), targets : Array(Target)) : Array(Target)
    targets.select { |t| ips.any? { |ip| t[:scrape_url].includes?("//#{ip}:") || t[:global_url].includes?("//#{ip}:") } }
  end

  def self.pod_ips(pods : Array(JSON::Any)) : Array(String)
    pods.flat_map { |pod| (pod.dig?("status", "podIPs").try(&.as_a?) || [] of JSON::Any).compact_map { |ip| ip["ip"]?.try(&.as_s?) } }
  end

  # One line on why no usable server was found, for the skip's details.
  def self.describe_missing(server : Server?) : String
    return "no process named #{CloudNativeIntrospection::PROMETHEUS_PROCESS} found in any ready container on the schedulable nodes" if server.nil?
    where = server[:service] ? "Service #{server[:service]}" : "no Service selecting it"
    tried = server[:probed].empty? ? "no TCP port to probe" : "the targets API did not answer at #{server[:probed].join(", ")}"
    "Prometheus process found in pod #{server[:pod]} in #{server[:namespace]} (#{where}); #{tried}"
  end

  def self.describe(server : Server) : String
    "Prometheus: pod #{server[:pod]} in #{server[:namespace]}, Service #{server[:service]}, targets API at #{server[:url]}, #{server[:targets].size} active target(s)"
  end

  def self.open_metric_validator(url)
    Log.info { "ClusterTools open_metric_validator" }
    cli = %(/bin/bash -c "curl -sS --max-time 10 #{url} | openmetricsvalidator")
    resp = ClusterTools.exec(cli)
    Log.info { "metrics resp: #{resp}"}
    resp
  end
end
