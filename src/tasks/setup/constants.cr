module Setup
  # Versions of the tools
  CLUSTER_API_VERSION         = "1.9.6"
  KIND_VERSION                = "0.27.0"
  KUBESCAPE_VERSION           = "3.0.30"
  KUBESCAPE_FRAMEWORK_VERSION = "1.0.316"
  # (rafal-lal) TODO: configure version of the gatekeeper
  GATEKEEPER_VERSION = "TODO: USE THIS"

  # Useful consts grouped by tools
  CLUSTER_API_URL = "https://github.com/kubernetes-sigs/cluster-api/releases/download/" +
                    "v#{CLUSTER_API_VERSION}/clusterctl-linux-amd64"
  CLUSTER_API_DIR   = "#{tools_path}/cluster-api"
  CLUSTERCTL_BINARY = "#{CLUSTER_API_DIR}/clusterctl"

  KIND_DOWNLOAD_URL = "https://github.com/kubernetes-sigs/kind/releases/download/v#{KIND_VERSION}/kind-linux-amd64"
  KIND_DIR          = "#{tools_path}/kind"

  KUBESCAPE_DIR = "#{tools_path}/kubescape"
  KUBESCAPE_URL = "https://github.com/armosec/kubescape/releases/download/" +
                  "v#{KUBESCAPE_VERSION}/kubescape-ubuntu-latest"
  KUBESCAPE_FRAMEWORK_URL = "https://github.com/armosec/regolibrary/releases/download/" +
                            "v#{KUBESCAPE_FRAMEWORK_VERSION}/nsa"

  GATEKEEPER_REPO = "https://open-policy-agent.github.io/gatekeeper/charts"
  SONOBUOY_DIR    = "#{tools_path}/sonobuoy"
  SONOBUOY_URL    = "https://github.com/vmware-tanzu/sonobuoy/releases/download/" +
                            "v#{SONOBUOY_K8S_VERSION}/sonobuoy_#{SONOBUOY_K8S_VERSION}_#{SONOBUOY_OS}_amd64.tar.gz"
  SONOBUOY_BINARY = "#{SONOBUOY_DIR}/sonobuoy"
end
