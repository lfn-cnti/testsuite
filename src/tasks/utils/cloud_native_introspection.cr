
require "colorize"
require "../../modules/kubectl_client"

module CloudNativeIntrospection
  PROMETHEUS_PROCESS = "prometheus"
  PROMETHEUS_ADAPTER = "adapter"
  STATE_METRICS_PROCESS = "kube-state-metrics"
  METRICS_SERVER = "metrics-server"
  NODE_EXPORTER = "node_exporter"
end
