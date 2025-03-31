module Setup
  CLUSTER_API_VERSION = "1.9.6"
  CLUSTER_API_URL     = "https://github.com/kubernetes-sigs/cluster-api/releases/download/" +
                        "v#{CLUSTER_API_VERSION}/clusterctl-linux-amd64"
  CLUSTER_API_DIR   = "#{tools_path}/cluster-api"
  CLUSTERCTL_BINARY = "#{CLUSTER_API_DIR}/clusterctl"
end
