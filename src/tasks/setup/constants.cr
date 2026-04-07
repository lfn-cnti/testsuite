module Setup
  TARGET_OS = begin
    {% if flag?(:darwin) %}
      "darwin"
    {% else %}
      "linux"
    {% end %}
  end

  TARGET_ARCH = begin
    {% if flag?(:aarch64) %}
      "arm64"
    {% else %}
      "amd64"
    {% end %}
  end

  KUBESCAPE_TARGET_BINARY_NAME = begin
    case {TARGET_OS, TARGET_ARCH}
    when {"darwin", "arm64"}
      "kubescape-arm64-macos-latest"
    when {"darwin", "amd64"}
      "kubescape-macos-latest"
    when {"linux", "arm64"}
      "kubescape-arm64-ubuntu-latest"
    else
      "kubescape-ubuntu-latest"
    end
  end

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
                       "v#{CLUSTER_API_VERSION}/clusterctl-#{TARGET_OS}-#{TARGET_ARCH}"
  CLUSTER_API_DIR    = "\#{tools_path}/cluster-api"
  CLUSTERCTL_BINARY  = "#{CLUSTER_API_DIR}/clusterctl"

  KIND_DOWNLOAD_URL  = "https://github.com/kubernetes-sigs/kind/releases/download/v#{KIND_VERSION}/kind-#{TARGET_OS}-#{TARGET_ARCH}"
  KIND_DIR           = "#{tools_path}/kind"

  KUBESCAPE_DIR      = "#{tools_path}/kubescape"
  KUBESCAPE_URL      = "https://github.com/kubescape/kubescape/releases/download/" +
                       "v#{KUBESCAPE_VERSION}/#{KUBESCAPE_TARGET_BINARY_NAME}"
  KUBESCAPE_FRAMEWORK_URL = "https://github.com/kubescape/regolibrary/releases/download/" +
                             "v#{KUBESCAPE_FRAMEWORK_VERSION}/nsa"

  GATEKEEPER_REPO    = "https://open-policy-agent.github.io/gatekeeper/charts"

  SONOBUOY_DIR       = "#{tools_path}/sonobuoy"
  SONOBUOY_URL       = "https://github.com/vmware-tanzu/sonobuoy/releases/download/" +
                       "v#{SONOBUOY_K8S_VERSION}/sonobuoy_#{SONOBUOY_K8S_VERSION}_#{TARGET_OS}-#{TARGET_ARCH}.tar.gz"
  SONOBUOY_BINARY    = "#{SONOBUOY_DIR}/sonobuoy"

  HELM_DIR           = "#{tools_path}/helm"
  HELM_URL           = "https://get.helm.sh/helm-v#{HELM_VERSION}-#{TARGET_OS}-#{TARGET_ARCH}.tar.gz"
  HELM_BINARY        = "#{HELM_DIR}/#{TARGET_OS}-#{TARGET_ARCH}/helm"
end
