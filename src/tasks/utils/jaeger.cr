module JaegerManager
  # renovate: datasource=helm depName=jaeger registryUrl=https://jaegertracing.github.io/helm-charts
  JAEGER_CHART_VERSION = "1.0.0"
  JAEGER_NAMESPACE = "jaeger"

  # Jaeger is configured when its query API answers: probing the thing the
  # test reads is more reliable than matching collector images on nodes
  # (which needs cluster-tools plus a registry digest lookup).
  def self.available? : Bool
    !query_api("/api/services").nil?
  end

  def self.uninstall
    Log.debug { "uninstall_jaeger" }
    Helm.uninstall("jaeger", JAEGER_NAMESPACE)
  rescue Helm::ShellCMD::ReleaseNotFound
    Log.info { "Jaeger release not found, nothing to uninstall" }
  end

  def self.install
    Log.info { "Installing Jaeger daemonset" }
    StatusLine.push "Installing Jaeger into the cluster (cassandra warm-up; this can take a few minutes)..."
    Helm.helm_repo_add("jaegertracing", "https://jaegertracing.github.io/helm-charts")
    CNFManager.ensure_namespace_exists!(JAEGER_NAMESPACE)
    Helm.install("jaeger", "jaegertracing/jaeger", namespace: JAEGER_NAMESPACE,
      values: "--version #{JAEGER_CHART_VERSION} --set cassandra.config.seed_size=1")
    # Cassandra readies first (the collector and query crash-loop until it
    # resolves), and an unready Jaeger must fail the install loudly (#2060):
    # every consumer of this install would otherwise silently skip.
    [ {"Statefulset", "jaeger-cassandra", 600},
      {"Deployment", "jaeger-collector", 300},
      {"Deployment", "jaeger-query", 300},
      {"Daemonset", "jaeger-agent", 300} ].each do |kind, name, wait_count|
      ready = KubectlClient::Wait.resource_wait_for_install(kind, name, wait_count, namespace: JAEGER_NAMESPACE)
      raise "Jaeger install failed: #{kind} #{name} did not become ready" unless ready
    end
    StatusLine.pop
  end

  # GET against the jaeger-query HTTP API through the API-server proxy: works
  # from outside the cluster, no in-cluster curl needed. Returns nil when the
  # call or the parse fails.
  def self.query_api(path : String) : JSON::Any?
    logger = Log.for("JaegerManager.query_api")
    cmd = "kubectl get --raw '/api/v1/namespaces/#{JAEGER_NAMESPACE}/services/jaeger-query:query/proxy#{path}'"
    result = KubectlClient::ShellCMD.raise_exc_on_error { KubectlClient::ShellCMD.run(cmd, logger) }
    JSON.parse(result[:output])
  rescue ex : KubectlClient::ShellCMD::K8sClientCMDException | JSON::ParseException
    logger = Log.for("JaegerManager.query_api")
    logger.warn { "Jaeger query API call #{path} failed: #{ex.message}" }
    nil
  end

  # Service names Jaeger knows traces for, without Jaeger's own components.
  def self.services : Array(String)
    json = query_api("/api/services")
    return [] of String unless json
    (json.dig?("data").try(&.as_a?) || [] of JSON::Any)
      .compact_map(&.as_s?)
      .reject { |name| name.starts_with?("jaeger") }
  end

  # The hostnames (pod names, for in-cluster clients) found in the process tags
  # of the service's recent traces.
  def self.trace_hostnames(service : String) : Set(String)
    hostnames = Set(String).new
    json = query_api("/api/traces?service=#{URI.encode_www_form(service)}&limit=20")
    return hostnames unless json
    (json.dig?("data").try(&.as_a?) || [] of JSON::Any).each do |trace|
      processes = trace.dig?("processes").try(&.as_h?) || next
      processes.each_value do |process|
        tags = process.dig?("tags").try(&.as_a?) || next
        tags.each do |tag|
          next unless tag.dig?("key").try(&.as_s?) == "hostname"
          hostname = tag.dig?("value").try(&.as_s?)
          hostnames << hostname if hostname
        end
      end
    end
    hostnames
  end
end
