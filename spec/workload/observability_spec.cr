require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/utils/fluent_manager.cr"
require "../../src/tasks/setup/jaeger_setup.cr"

describe "Observability" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "'log_output' should pass with a cnf that outputs logs to stdout", tags: ["observability"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("log_output")
      result[:status].success?.should be_true
      (/(PASSED).*(Resources output logs to stdout and stderr)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'log_output' should fail with a cnf that does not output logs to stdout", tags: ["observability"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample_no_logs/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("log_output")
      result[:status].success?.should be_true
      (/(FAILED).*(Resources do not output logs to stdout and stderr)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'prometheus_traffic' should pass if there is prometheus traffic", tags: ["observability"] do
    ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-prom-pod-discovery/cnf-testsuite.yml")
    helm = Helm::Binary.get

    Log.info { "Add prometheus helm repo" }
    ShellCmd.run("#{helm} repo add prometheus-community https://prometheus-community.github.io/helm-charts", "helm_repo_add_prometheus", force_output: true)

    Log.info { "Installing prometheus server" }
    install_cmd = "#{helm} install -n #{TESTSUITE_NAMESPACE} --set alertmanager.persistentVolume.enabled=false --set server.persistentVolume.enabled=false --set pushgateway.persistentVolume.enabled=false prometheus prometheus-community/prometheus"
    ShellCmd.run(install_cmd, "helm_install_prometheus", force_output: true)

    KubectlClient::Wait.resource_wait_for_install("deployment", "prometheus-server", namespace: TESTSUITE_NAMESPACE)
    ShellCmd.run("kubectl describe deployment prometheus-server -n #{TESTSUITE_NAMESPACE}", "k8s_describe_prometheus", force_output: true)

    test_result = ShellCmd.run_testsuite("prometheus_traffic")
    (/(PASSED).*(Your cnf is sending prometheus traffic)/ =~ test_result[:output]).should_not be_nil
  ensure
    ShellCmd.cnf_uninstall()
    result = ShellCmd.run("#{helm} delete prometheus -n #{TESTSUITE_NAMESPACE}", "helm_delete_prometheus")
    result[:status].success?.should be_true
  end

  it "'prometheus_traffic' should skip if there is no prometheus installed", tags: ["observability"] do

      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      helm = Helm::Binary.get
      result = ShellCmd.run("#{helm} delete prometheus -n #{TESTSUITE_NAMESPACE}", force_output: true)

      result = ShellCmd.run_testsuite("prometheus_traffic")
      (/(SKIPPED).*(Prometheus server not found)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
  end

  it "'prometheus_traffic' should fail if the cnf is not registered with prometheus", tags: ["observability"] do

      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      Log.info { "Installing prometheus server" }
      helm = Helm::Binary.get
      result = ShellCmd.run("helm repo add prometheus-community https://prometheus-community.github.io/helm-charts", force_output: true)
      result = ShellCmd.run("#{helm} install -n #{TESTSUITE_NAMESPACE} --set alertmanager.persistentVolume.enabled=false --set server.persistentVolume.enabled=false --set pushgateway.persistentVolume.enabled=false prometheus prometheus-community/prometheus", force_output: true)
      KubectlClient::Wait.resource_wait_for_install("deployment", "prometheus-server", namespace: TESTSUITE_NAMESPACE)
      result = ShellCmd.run("kubectl describe deployment prometheus-server", force_output: true)
      #todo logging on prometheus pod

      result = ShellCmd.run_testsuite("prometheus_traffic")
      (/(FAILED).*(Your cnf is not sending prometheus traffic)/ =~ result[:output]).should_not be_nil
  ensure
      result = ShellCmd.cnf_uninstall()
      result = ShellCmd.run("#{helm} delete prometheus -n #{TESTSUITE_NAMESPACE}", force_output: true)
      result[:status].success?.should be_true
  end

  it "'open_metrics' should fail if there is not a valid open metrics response from the cnf", tags: ["observability"] do
    ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-prom-pod-discovery/cnf-testsuite.yml")
    result = ShellCmd.run("helm repo add prometheus-community https://prometheus-community.github.io/helm-charts", force_output: true)
    Log.info { "Installing prometheus server" }
    helm = Helm::Binary.get
    result = ShellCmd.run("#{helm} install -n #{TESTSUITE_NAMESPACE} --set alertmanager.persistentVolume.enabled=false --set server.persistentVolume.enabled=false --set pushgateway.persistentVolume.enabled=false prometheus prometheus-community/prometheus", force_output: true)
    KubectlClient::Wait.resource_wait_for_install("deployment", "prometheus-server", namespace: TESTSUITE_NAMESPACE)
    result = ShellCmd.run("kubectl describe deployment prometheus-server -n #{TESTSUITE_NAMESPACE}", force_output: true)
    #todo logging on prometheus pod

    result = ShellCmd.run_testsuite("open_metrics")
    (/(FAILED).*(Your cnf's metrics traffic is not OpenMetrics compatible)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    result = ShellCmd.run("#{helm} delete prometheus -n #{TESTSUITE_NAMESPACE}", force_output: true)
    result[:status].success?.should be_true
  end

  it "'open_metrics' should pass if there is a valid open metrics response from the cnf", tags: ["observability"] do
    ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-openmetrics/cnf-testsuite.yml")
    result = ShellCmd.run("helm repo add prometheus-community https://prometheus-community.github.io/helm-charts", force_output: true)
    Log.info { "Installing prometheus server" }
    helm = Helm::Binary.get
    result = ShellCmd.run("#{helm} install -n #{TESTSUITE_NAMESPACE} --set alertmanager.persistentVolume.enabled=false --set server.persistentVolume.enabled=false --set pushgateway.persistentVolume.enabled=false prometheus prometheus-community/prometheus", force_output: true)
    KubectlClient::Wait.resource_wait_for_install("deployment", "prometheus-server", namespace: TESTSUITE_NAMESPACE)
    result = ShellCmd.run("kubectl describe deployment prometheus-server -n #{TESTSUITE_NAMESPACE}", force_output: true)
    #todo logging on prometheus pod

    result = ShellCmd.run_testsuite("open_metrics")
    (/(PASSED).*(Your cnf's metrics traffic is OpenMetrics compatible)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    result = ShellCmd.run("#{helm} delete prometheus -n #{TESTSUITE_NAMESPACE}", force_output: true)
    result[:status].success?.should be_true
  end

  it "'routed_logs' should pass if cnfs logs are captured by fluentd bitnami", tags: ["observability"] do
    ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
    result = ShellCmd.run_testsuite("setup:install_fluentdbitnami")
    result = ShellCmd.run_testsuite("routed_logs")
    (/(PASSED).*(Your CNF's logs are being captured)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    result = ShellCmd.run_testsuite("setup:uninstall_fluentdbitnami")
    result[:status].success?.should be_true
  end

  it "'routed_logs' should pass if cnfs logs are captured by fluentbit", tags: ["observability"] do
    ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-fluentbit")
    result = ShellCmd.run_testsuite("setup:install_fluentbit")
    result = ShellCmd.run_testsuite("routed_logs")
    (/(PASSED).*(Your CNF's logs are being captured)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    result = ShellCmd.run_testsuite("setup:uninstall_fluentbit")
    result[:status].success?.should be_true
  end

  it "'routed_logs' should fail if cnfs logs are not captured", tags: ["observability"] do
    ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
    Helm.helm_repo_add("bitnami","https://charts.bitnami.com/bitnami")
    #todo  #helm install --values ./override.yml fluentd ./fluentd
    Helm.install("fluentd", "bitnami/fluentd", namespace: TESTSUITE_NAMESPACE, values: "--values ./spec/fixtures/fluentd-values-bad.yml")
    Log.info { "Installing FluentD daemonset" }
    KubectlClient::Wait.resource_wait_for_install("Daemonset", "fluentd", namespace: TESTSUITE_NAMESPACE)
    result = ShellCmd.run_testsuite("routed_logs")
    (/(FAILED).*(Your CNF's logs are not being captured)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    result = ShellCmd.run_testsuite("setup:uninstall_fluentd")
    result[:status].success?.should be_true
  end

  it "'tracing' should fail if tracing is not used", tags: ["observability_jaeger_fail"] do
    # (kosstennbl) TODO: Test and specs for 'tracing' should be redesigned. Check #2153 for more info. Spec was using sample-coredns-cnf CNF.
  end

  it "'tracing' should pass if tracing is used", tags: ["observability_jaeger_pass"] do
    # (kosstennbl) TODO: Test and specs for 'tracing' should be redesigned. Check #2153 for more info. Spec was using sample-tracing CNF.
  end
end
