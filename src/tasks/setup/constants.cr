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

  # Versions of the tools
  # renovate: datasource=github-releases depName=kubernetes-sigs/cluster-api
  CLUSTER_API_VERSION         = "1.14.0"
  # renovate: datasource=github-releases depName=kubernetes-sigs/kind
  KIND_VERSION                = "0.32.0"
  # renovate: datasource=github-releases depName=kubescape/kubescape
  KUBESCAPE_VERSION           = "4.0.12"
  # renovate: datasource=github-releases depName=kubescape/regolibrary
  KUBESCAPE_FRAMEWORK_VERSION = "2.0.33"
  # renovate: datasource=github-releases depName=helm/helm
  HELM_VERSION                = "3.21.4"
  # renovate: datasource=helm depName=gatekeeper registryUrl=https://open-policy-agent.github.io/gatekeeper/charts
  GATEKEEPER_VERSION          = "3.23.0"

  # Useful consts grouped by tools
  CLUSTER_API_URL    = "https://github.com/kubernetes-sigs/cluster-api/releases/download/" +
                       "v#{CLUSTER_API_VERSION}/clusterctl-#{TARGET_OS}-#{TARGET_ARCH}"

  CLUSTER_API_DIR    = "#{tools_path}/cluster-api"
  CLUSTERCTL_BINARY  = "#{CLUSTER_API_DIR}/clusterctl"

  # Manifests and helm values the suite renders at runtime. Kept with the
  # tools rather than scattered into the user's working directory: a run must
  # only ever touch the cnti/ workspace in the CWD.
  RENDERED_MANIFESTS_DIR = "#{tools_path}/rendered-manifests"
  CLUSTER_TOOLS_MANIFEST = "#{RENDERED_MANIFESTS_DIR}/cluster_tools.yml"
  FIVE_G_TOOLS_DIR       = "#{tools_path}/5g"

  KIND_DOWNLOAD_URL  = "https://github.com/kubernetes-sigs/kind/releases/download/v#{KIND_VERSION}/kind-#{TARGET_OS}-#{TARGET_ARCH}"
  KIND_DIR           = "#{tools_path}/kind"
  KIND_BINARY        = "#{KIND_DIR}/kind"

  KUBESCAPE_DIR      = "#{tools_path}/kubescape"
  KUBESCAPE_URL      = "https://github.com/kubescape/kubescape/releases/download/" +
                       "v#{KUBESCAPE_VERSION}/kubescape_#{KUBESCAPE_VERSION}_#{TARGET_OS}_#{TARGET_ARCH}.tar.gz"
  KUBESCAPE_BINARY   = "#{KUBESCAPE_DIR}/kubescape"
  KUBESCAPE_FRAMEWORK_URL = "https://github.com/kubescape/regolibrary/releases/download/" +
                             "v#{KUBESCAPE_FRAMEWORK_VERSION}/nsa"

  GATEKEEPER_REPO    = "https://open-policy-agent.github.io/gatekeeper/charts"

  SONOBUOY_DIR       = "#{tools_path}/sonobuoy"
  SONOBUOY_URL       = "https://github.com/vmware-tanzu/sonobuoy/releases/download/" +
                       "v#{SONOBUOY_K8S_VERSION}/sonobuoy_#{SONOBUOY_K8S_VERSION}_#{TARGET_OS}_#{TARGET_ARCH}.tar.gz"
  SONOBUOY_BINARY    = "#{SONOBUOY_DIR}/sonobuoy"

  HELM_DIR           = "#{tools_path}/helm"
  HELM_URL           = "https://get.helm.sh/helm-v#{HELM_VERSION}-#{TARGET_OS}-#{TARGET_ARCH}.tar.gz"
  HELM_BINARY        = "#{HELM_DIR}/#{TARGET_OS}-#{TARGET_ARCH}/helm"
end
