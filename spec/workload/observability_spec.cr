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


  it "'log_output' should pass with a cnf that outputs logs to stdout", tags: ["observability_log_output"]  do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("log_output")
      result[:status].success?.should be_true
      (/(PASSED).*(Resources output logs to stdout and stderr)/ =~ result[:output]).should_not be_nil
      (/> [A-Za-z]+\/.* in .*: logs from / =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'log_output' should fail with a cnf that does not output logs to stdout", tags: ["observability_log_output"]  do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_no_logs/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("log_output")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Resources do not output logs to stdout and stderr)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'log_output' should be skipped when no pod is running yet", tags: ["observability_log_output"] do
    begin
      # A pod that never schedules has nothing to log; kubectl returns no
      # output and no error for it, which used to count as "quiet" (#2488).
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-unschedulable --skip-wait-for-install")
      result = ShellCmd.run_testsuite("log_output")
      result[:status].success?.should be_true
      (/(SKIPPED).*(Log output not checked)/ =~ result[:output]).should_not be_nil
      result[:output].should contain("Logs could not be read: Deployment/unschedulable")
      result[:output].should contain("pod is Pending")
      verify_task_result("log_output", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'log_output' should be skipped, not crash, when a pod's logs cannot be read", tags: ["observability_log_output"] do
    begin
      # The image can never be pulled, so `kubectl logs` errors; that used to
      # be an unhandled exception (exit 2) rather than a verdict (#2488).
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-unpullable-image --skip-wait-for-install")
      result = ShellCmd.run_testsuite("log_output")
      result[:status].success?.should be_true
      (/(SKIPPED).*(Log output not checked)/ =~ result[:output]).should_not be_nil
      result[:output].should contain("Logs could not be read: Deployment/unpullable-image")
      verify_task_result("log_output", "skipped")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
    end
  end

  it "'prometheus_traffic' should pass if there is prometheus traffic", tags: ["observability_prometheus_traffic"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-prom-pod-discovery/cnti-testsuite.yaml")
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

  it "'prometheus_traffic' should skip if there is no prometheus installed", tags: ["observability_prometheus_traffic"] do

      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      helm = Helm::Binary.get
      result = ShellCmd.run("#{helm} delete prometheus -n #{TESTSUITE_NAMESPACE}", force_output: true)

      result = ShellCmd.run_testsuite("prometheus_traffic")
      (/(SKIPPED).*(Prometheus server not found)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
  end

  it "'prometheus_traffic' should fail if the cnf is not registered with prometheus", tags: ["observability_prometheus_traffic"] do

      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
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

  it "'open_metrics' should fail if there is not a valid open metrics response from the cnf", tags: ["observability_open_metrics"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-prom-pod-discovery/cnti-testsuite.yaml")
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

  it "'open_metrics' should pass if there is a valid open metrics response from the cnf", tags: ["observability_open_metrics"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-openmetrics/cnti-testsuite.yaml")
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

  it "'routed_logs' should pass if cnfs logs are captured by fluentd", tags: ["observability_routed_logs"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
    result = ShellCmd.run_testsuite("setup:install_fluentd")
    result = ShellCmd.run_testsuite("routed_logs")
    (/(PASSED).*(Your CNF's logs are being captured)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    result = ShellCmd.run_testsuite("setup:uninstall_fluentd")
    result[:status].success?.should be_true
  end

  it "'routed_logs' should pass if cnfs logs are captured by fluentbit", tags: ["observability_routed_logs"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-fluentbit")
    result = ShellCmd.run_testsuite("setup:install_fluentbit")
    result = ShellCmd.run_testsuite("routed_logs")
    (/(PASSED).*(Your CNF's logs are being captured)/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    result = ShellCmd.run_testsuite("setup:uninstall_fluentbit")
    result[:status].success?.should be_true
  end

  it "'routed_logs' should fail if cnfs logs are not captured", tags: ["observability_routed_logs"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
    Helm.helm_repo_add("fluentd", "https://fluent.github.io/helm-charts")
    Helm.install("fluentd", "fluentd/fluentd", namespace: TESTSUITE_NAMESPACE, values: "--values ./spec/fixtures/fluentd-values-bad.yml")
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
    begin
      result = ShellCmd.run_testsuite("setup:install_jaeger")
      result[:status].success?.should be_true
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("tracing")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Tracing not used)/ =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/coredns-coredns in cnti-default: no traces in Jaeger/ =~ result[:output]).should_not be_nil
      verify_task_result("tracing", "failed")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      ShellCmd.run_testsuite("setup:uninstall_jaeger")
    end
  end

  it "'tracing' should pass if tracing is used", tags: ["observability_jaeger_pass"] do
    begin
      result = ShellCmd.run_testsuite("setup:install_jaeger")
      result[:status].success?.should be_true
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-tracing/cnti-testsuite.yaml")
      # HotROD only emits spans when it serves a request.
      attempts = 0
      result = loop do
        ShellCmd.run("kubectl get --raw '/api/v1/namespaces/tracing/services/hotrod:http/proxy/dispatch?customer=123'", "hotrod_request")
        sleep 10.seconds
        run = ShellCmd.run_testsuite("tracing")
        attempts += 1
        break run if run[:status].success? || attempts >= 3
      end
      result[:status].success?.should be_true
      (/(PASSED).*(Tracing used)/ =~ result[:output]).should_not be_nil
      (/Deployment\/hotrod: traces in Jaeger from hotrod-.* \(service / =~ result[:output]).should_not be_nil
      verify_task_result("tracing", "passed")
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      ShellCmd.run_testsuite("setup:uninstall_jaeger")
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
