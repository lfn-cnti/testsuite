module Setup
  DEFAULT_OS    = "linux"
  DEFAULT_ARCH  = "amd64"

  # Versions of the tools
  CLUSTER_API_VERSION         = "1.9.6"
  KIND_VERSION                = "0.27.0"
  KUBESCAPE_VERSION           = "3.0.30"
  KUBESCAPE_FRAMEWORK_VERSION = "1.0.316"
  HELM_VERSION                = "3.19.0"
  # (rafal-lal) TODO: configure version of the gatekeeper
  GATEKEEPER_VERSION          = "TODO: USE THIS"

  # Useful consts grouped by tools
  CLUSTER_API_URL    = "https://github.com/kubernetes-sigs/cluster-api/releases/download/" +
                       "v#{CLUSTER_API_VERSION}/clusterctl-#{DEFAULT_OS}-#{DEFAULT_ARCH}"
  CLUSTER_API_DIR    = "\#{tools_path}/cluster-api"
  CLUSTERCTL_BINARY  = "#{CLUSTER_API_DIR}/clusterctl"

  KIND_DOWNLOAD_URL  = "https://github.com/kubernetes-sigs/kind/releases/download/v#{KIND_VERSION}/kind-#{DEFAULT_OS}-#{DEFAULT_ARCH}"
  KIND_DIR           = "#{tools_path}/kind"

  KUBESCAPE_DIR      = "#{tools_path}/kubescape"
  KUBESCAPE_URL      = "https://github.com/kubescape/kubescape/releases/download/" +
                       "v#{KUBESCAPE_VERSION}/kubescape-ubuntu-latest"
  KUBESCAPE_FRAMEWORK_URL = "https://github.com/kubescape/regolibrary/releases/download/" +
                             "v#{KUBESCAPE_FRAMEWORK_VERSION}/nsa"

  GATEKEEPER_REPO    = "https://open-policy-agent.github.io/gatekeeper/charts"

  SONOBUOY_DIR       = "#{tools_path}/sonobuoy"
  SONOBUOY_URL       = "https://github.com/vmware-tanzu/sonobuoy/releases/download/" +
                       "v#{SONOBUOY_K8S_VERSION}/sonobuoy_#{SONOBUOY_K8S_VERSION}_#{DEFAULT_OS}-#{DEFAULT_ARCH}.tar.gz"
  SONOBUOY_BINARY    = "#{SONOBUOY_DIR}/sonobuoy"

  HELM_DIR           = "#{tools_path}/helm"
  HELM_URL           = "https://get.helm.sh/helm-v#{HELM_VERSION}-#{DEFAULT_OS}-#{DEFAULT_ARCH}.tar.gz"
  HELM_BINARY        = "#{HELM_DIR}/#{DEFAULT_OS}-#{DEFAULT_ARCH}/helm"
end
