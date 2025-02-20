require "./../spec_helper"
require "colorize"
require "./../../src/tasks/utils/utils.cr"
require "kubectl_client"

describe "Platform Observability" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "'kube_state_metrics' should return some json", tags: ["platform:observability"] do

      Log.info { "Installing kube_state_metrics" }
      helm = Helm::BinarySingleton.helm
      result = ShellCmd.run("#{helm} repo add prometheus-community https://prometheus-community.github.io/helm-charts")
      result = ShellCmd.run("#{helm} repo update")
      result = ShellCmd.run("#{helm} -n #{TESTSUITE_NAMESPACE} install --version 5.3.0 kube-state-metrics prometheus-community/kube-state-metrics", force_output: true)
      KubectlClient::Wait.resource_wait_for_install("deployment", "kube-state-metrics", namespace: TESTSUITE_NAMESPACE)

      result = ShellCmd.run_testsuite("platform:kube_state_metrics poc")
      (/(PASSED).*(Your platform is using the).*(release for kube state metrics)/ =~ result[:output]).should_not be_nil
  ensure
      result = ShellCmd.run("#{helm} delete kube-state-metrics -n #{TESTSUITE_NAMESPACE}", force_output: true)
      result[:status].success?.should be_true
  end

  it "'node_exporter' should detect the named release of the installed node_exporter", tags: ["platform:observability"] do

      Log.info { "Installing prometheus-node-exporter" }
      helm = Helm::BinarySingleton.helm
      Helm.helm_repo_add("prometheus-community","https://prometheus-community.github.io/helm-charts")
      result = ShellCmd.run("#{helm} install -n #{TESTSUITE_NAMESPACE} node-exporter prometheus-community/prometheus-node-exporter", force_output: true)

      repeat_with_timeout(timeout: POD_READINESS_TIMEOUT, errormsg: "Pod readiness has timed-out") do
        pod_ready = KubectlClient::Get.pod_ready?("node-exporter-prometheus", namespace: TESTSUITE_NAMESPACE)
        pod_ready
      end
      result = ShellCmd.run_testsuite("platform:node_exporter poc")
      if check_containerd
        (/(PASSED).*(Your platform is using the node exporter)/ =~ result[:output]).should_not be_nil
      else
        (/skipping node_exporter: This test only supports the Containerd Runtime./ =~ result[:output]).should_not be_nil
      end
  ensure
      result = ShellCmd.run("#{helm} delete node-exporter -n #{TESTSUITE_NAMESPACE}", force_output: true)
      result[:status].success?.should be_true
  end

  it "'prometheus_adapter' should detect the named release of the installed prometheus_adapter", tags: ["platform:observability"] do
    Log.info { "Installing prometheus-adapter" }
    helm = Helm::BinarySingleton.helm
    begin
      Helm.helm_repo_add("prometheus-community","https://prometheus-community.github.io/helm-charts")
      result = Helm.install("prometheus-adapter", "prometheus-community/prometheus-adapter", namespace: TESTSUITE_NAMESPACE)
      Log.info { "Prometheus installed" }
    rescue e : Helm::CannotReuseReleaseNameError
      Log.info { "Prometheus already installed" }
    end
    KubectlClient::Wait.resource_wait_for_install("deployment", "prometheus-adapter", namespace: TESTSUITE_NAMESPACE)

    result = ShellCmd.run_testsuite("platform:prometheus_adapter poc")
    (/(PASSED).*(Your platform is using the prometheus adapter)/ =~ result[:output]).should_not be_nil
  ensure
    resp = Helm.uninstall("prometheus-adapter -n #{TESTSUITE_NAMESPACE}")
  end

  it "'metrics_server' should detect the named release of the installed metrics_server", tags: ["platform:observability"] do
    Log.info { "Installing metrics-server" }
    helm = Helm::BinarySingleton.helm
    begin
      Helm.helm_repo_add("metrics-server","https://kubernetes-sigs.github.io/metrics-server/")
      result = Helm.install("metrics-server", "metrics-server/metrics-server", namespace: TESTSUITE_NAMESPACE, values: "--values spec/fixtures/metrics_values.yml")
      Log.info { "Metrics Server installed" }
    rescue e : Helm::CannotReuseReleaseNameError
      Log.info { "Metrics Server already installed" }
    end
      Log.info { result }
      KubectlClient::Wait.resource_wait_for_install("deployment", "metrics-server", namespace: TESTSUITE_NAMESPACE)
      result = ShellCmd.run_testsuite("platform:metrics_server poc")
      (/(PASSED).*(Your platform is using the metrics server)/ =~ result[:output]).should_not be_nil
  ensure
    result = Helm.uninstall("metrics-server -n #{TESTSUITE_NAMESPACE}")
    Log.info { result }
    result[:status].success?.should be_true
  end
end

