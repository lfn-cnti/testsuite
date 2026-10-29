require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/utils/fluent_manager.cr"
require "../../src/tasks/setup/jaeger_setup.cr"

# renovate: datasource=helm depName=prometheus registryUrl=https://prometheus-community.github.io/helm-charts
PROMETHEUS_CHART_VERSION = "29.39.0"

# Installs Prometheus into the suite's namespace and waits for its server.
# Through the suite's Helm helpers, so a transient network error is retried
# and a failed install fails the example with Helm's own message, instead of
# leaving it to fail later on a server that was never installed.
private def install_prometheus
  fail "helm repo add prometheus-community failed" unless Helm.helm_repo_add("prometheus-community", "https://prometheus-community.github.io/helm-charts")
  # repo add leaves a repository that already exists as it is, and the
  # self-hosted runners keep Helm's repositories between jobs: refresh the
  # index, or the pinned version may not be in it.
  updated = false
  3.times do |attempt|
    break if (updated = Helm.repo_update("prometheus-community"))
    sleep 5.seconds unless attempt == 2
  end
  fail "helm repo update prometheus-community failed" unless updated
  Helm.install("prometheus", "prometheus-community/prometheus", namespace: TESTSUITE_NAMESPACE,
    values: "--version #{PROMETHEUS_CHART_VERSION} --set alertmanager.persistence.enabled=false --set server.persistentVolume.enabled=false")
  KubectlClient::Wait.resource_wait_for_install("deployment", "prometheus-server", namespace: TESTSUITE_NAMESPACE).should be_true
end

# Deletes the Prometheus release: nil when that worked or there was none,
# the error otherwise.
private def delete_prometheus : String?
  result = ShellCmd.run("#{Helm::Binary.get} delete prometheus -n #{TESTSUITE_NAMESPACE} --ignore-not-found", "helm_delete_prometheus")
  result[:status].success? ? nil : (result[:error].presence || result[:output]).strip
rescue ex
  ex.message.to_s
end

# Runs the block with Prometheus installed, and removes it afterwards. A
# removal that fails fails an example that passed, so no release is left for
# the next install to trip over; after a failure in the block it is only
# printed, so it cannot replace that failure.
private def with_prometheus(&)
  passed = false
  begin
    install_prometheus
    yield
    passed = true
  ensure
    if error = delete_prometheus
      if passed
        fail "cleanup: helm delete prometheus: #{error}"
      else
        puts "cleanup: helm delete prometheus: #{error}"
      end
    end
  end
end

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
    with_prometheus do
      test_result = ShellCmd.run_testsuite("prometheus_traffic")
      (/(PASSED).*(Your cnf is sending prometheus traffic)/ =~ test_result[:output]).should_not be_nil
      (/> Prometheus: pod prometheus-server-\S+ in cnti-testsuite, Service prometheus-server, targets API at http:\/\/prometheus-server.cnti-testsuite.svc.cluster.local:80, \d+ active target\(s\)/ =~ test_result[:output]).should_not be_nil
      (/> Deployment\/coredns-coredns in .*: scraped at http:\/\/[\d.]+:9153\/metrics \(health \w+/ =~ test_result[:output]).should_not be_nil
      verify_task_result("prometheus_traffic", "passed")
    end
  ensure
    ShellCmd.cnf_uninstall()
  end

  it "'prometheus_traffic' should skip if there is no prometheus installed", tags: ["observability_prometheus_traffic"] do

      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      # No Prometheus for this one: a release left behind must be removed first.
      delete_prometheus.should be_nil

      result = ShellCmd.run_testsuite("prometheus_traffic")
      (/(N\/A).*(Prometheus server not found)/ =~ result[:output]).should_not be_nil
      (/> no process named prometheus found in any ready container/ =~ result[:output]).should_not be_nil
      verify_task_result("prometheus_traffic", "na")
    ensure
      result = ShellCmd.cnf_uninstall()
  end

  it "'prometheus_traffic' should fail if the cnf is not registered with prometheus", tags: ["observability_prometheus_traffic"] do

      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-coredns-cnf/cnti-testsuite.yaml")
      with_prometheus do
        result = ShellCmd.run_testsuite("prometheus_traffic")
        (/(FAILED).*(Your cnf is not sending prometheus traffic: 1 workload\(s\) not scraped)/ =~ result[:output]).should_not be_nil
        (/> Prometheus: pod prometheus-server-\S+ in cnti-testsuite, Service prometheus-server, targets API at http:\/\/prometheus-server.cnti-testsuite.svc.cluster.local:80/ =~ result[:output]).should_not be_nil
        (/impacted: Deployment\/coredns-coredns in cnti-default: none of Prometheus's \d+ active targets scrapes its pods \(pod IPs [\d., ]+\)/ =~ result[:output]).should_not be_nil
        verify_task_result("prometheus_traffic", "failed")
      end
  ensure
      ShellCmd.cnf_uninstall()
  end

  it "'open_metrics' should fail if there is not a valid open metrics response from the cnf", tags: ["observability_open_metrics"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-prom-pod-discovery/cnti-testsuite.yaml")
    with_prometheus do
      result = ShellCmd.run_testsuite("open_metrics")
      (/(FAILED).*(Your cnf's metrics traffic is not OpenMetrics compatible)/ =~ result[:output]).should_not be_nil
      (/> Deployment\/coredns-coredns in .*: http:\/\/[\d.]+:9153\/metrics failed validation: / =~ result[:output]).should_not be_nil
      (/impacted: Deployment\/coredns-coredns in .*: metrics at http:\/\/[\d.]+:9153\/metrics are not OpenMetrics compatible: / =~ result[:output]).should_not be_nil
      verify_task_result("open_metrics", "failed")
    end
  ensure
    ShellCmd.cnf_uninstall()
  end

  it "'open_metrics' should pass if there is a valid open metrics response from the cnf", tags: ["observability_open_metrics"] do
    ShellCmd.cnf_install("--cnf-config sample-cnfs/sample-openmetrics/cnti-testsuite.yaml")
    with_prometheus do
      result = ShellCmd.run_testsuite("open_metrics")
      (/(PASSED).*(Your cnf's metrics traffic is OpenMetrics compatible)/ =~ result[:output]).should_not be_nil
      (/> Pod\/metrics-example in cnfspace: http:\/\/[\d.]+:80\/metrics is OpenMetrics compatible/ =~ result[:output]).should_not be_nil
      verify_task_result("open_metrics", "passed")
    end
  ensure
    ShellCmd.cnf_uninstall()
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

  it "'termination_message_policy' should pass when every container falls back to its log", tags: ["termination_message_policy"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_termination_message_policy/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("termination_message_policy")
      result[:status].success?.should be_true
      # The init container counts too: two containers judged.
      (/(PASSED).*(All 2 container\(s\) set terminationMessagePolicy: FallbackToLogsOnError)/ =~ result[:output]).should_not be_nil
      verify_task_result("termination_message_policy", "passed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'termination_message_policy' should fail when a container leaves the policy unset", tags: ["termination_message_policy"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_termination_message_policy_fail/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("termination_message_policy")
      result[:status].exit_code.should eq(1)
      (/(FAILED).*(Found 1 of 1 container\(s\) without terminationMessagePolicy: FallbackToLogsOnError)/ =~ result[:output]).should_not be_nil
      # Unset is defaulted to File by the API server, and the finding says so.
      (/impacted: Deployment\/termination-message-unset.*container app.*terminationMessagePolicy is File \(File is also the default when unset\)/ =~ result[:output]).should_not be_nil
      verify_task_result("termination_message_policy", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'termination_message_policy' should fail on an init container without the policy", tags: ["termination_message_policy"] do
    begin
      ShellCmd.cnf_install("--cnf-config sample-cnfs/sample_termination_message_policy_init/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("termination_message_policy")
      result[:status].exit_code.should eq(1)
      # Only the init container is unset; the regular one must not be named.
      (/impacted: Deployment\/termination-message-init.*container init.*init container terminationMessagePolicy is File/ =~ result[:output]).should_not be_nil
      (/impacted: .*container app/ =~ result[:output]).should be_nil
      verify_task_result("termination_message_policy", "failed")
    ensure
      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  after_all do
    result = ShellCmd.run_testsuite("uninstall_all")
  end
end
