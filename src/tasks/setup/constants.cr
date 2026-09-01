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
  # renovate: datasource=github-releases depName=kubescape/kubescape
  KUBESCAPE_VERSION           = "4.0.12"
  # renovate: datasource=github-releases depName=kubescape/regolibrary
  KUBESCAPE_FRAMEWORK_VERSION = "2.0.33"
  # renovate: datasource=github-releases depName=helm/helm
  HELM_VERSION                = "4.2.4"
  # renovate: datasource=helm depName=gatekeeper registryUrl=https://open-policy-agent.github.io/gatekeeper/charts
  GATEKEEPER_VERSION          = "3.23.0"

  # Useful consts grouped by tools


  # Manifests and helm values the suite renders at runtime. Kept with the
  # tools rather than scattered into the user's working directory: a run must
  # only ever touch the cnti/ workspace in the CWD.
  RENDERED_MANIFESTS_DIR = "#{tools_path}/rendered-manifests"
  CLUSTER_TOOLS_MANIFEST = "#{RENDERED_MANIFESTS_DIR}/cluster_tools.yml"


  KUBESCAPE_DIR      = "#{tools_path}/kubescape"
  KUBESCAPE_URL      = "https://github.com/kubescape/kubescape/releases/download/" +
                       "v#{KUBESCAPE_VERSION}/kubescape_#{KUBESCAPE_VERSION}_#{TARGET_OS}_#{TARGET_ARCH}.tar.gz"
  KUBESCAPE_BINARY   = "#{KUBESCAPE_DIR}/kubescape"
  KUBESCAPE_FRAMEWORK_URL = "https://github.com/kubescape/regolibrary/releases/download/" +
                             "v#{KUBESCAPE_FRAMEWORK_VERSION}/nsa"

  GATEKEEPER_REPO    = "https://open-policy-agent.github.io/gatekeeper/charts"


  HELM_DIR           = "#{tools_path}/helm"
  HELM_URL           = "https://get.helm.sh/helm-v#{HELM_VERSION}-#{TARGET_OS}-#{TARGET_ARCH}.tar.gz"
  HELM_BINARY        = "#{HELM_DIR}/#{TARGET_OS}-#{TARGET_ARCH}/helm"
end
