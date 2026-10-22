require "./spec_helper"
require "colorize"
require "../src/tasks/utils/utils.cr"

# Admission policies the specs below put in place to make the cluster refuse
# what the suite needs, so the suite's own messages can be checked.
DENY_CLUSTER_TOOLS_PODS = <<-YAML
  apiVersion: admissionregistration.k8s.io/v1
  kind: ValidatingAdmissionPolicy
  metadata:
    name: cnti-spec-deny-cluster-tools
  spec:
    failurePolicy: Fail
    matchConstraints:
      resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
    validations:
    - expression: "!(has(object.metadata.labels) && 'name' in object.metadata.labels && object.metadata.labels['name'] == 'cluster-tools')"
      message: "cnti spec: cluster-tools pods are denied here"
  ---
  apiVersion: admissionregistration.k8s.io/v1
  kind: ValidatingAdmissionPolicyBinding
  metadata:
    name: cnti-spec-deny-cluster-tools
  spec:
    policyName: cnti-spec-deny-cluster-tools
    validationActions: [Deny]
    matchResources:
      namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: cnti-testsuite
  YAML

DENY_PRIVILEGED_LABEL = <<-YAML
  apiVersion: admissionregistration.k8s.io/v1
  kind: ValidatingAdmissionPolicy
  metadata:
    name: cnti-spec-deny-privileged-label
  spec:
    failurePolicy: Fail
    matchConstraints:
      resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["namespaces"]
    validations:
    - expression: "!(has(object.metadata.labels) && 'pod-security.kubernetes.io/enforce' in object.metadata.labels && object.metadata.labels['pod-security.kubernetes.io/enforce'] == 'privileged')"
      message: "cnti spec: privileged namespaces are denied here"
  ---
  apiVersion: admissionregistration.k8s.io/v1
  kind: ValidatingAdmissionPolicyBinding
  metadata:
    name: cnti-spec-deny-privileged-label
  spec:
    policyName: cnti-spec-deny-privileged-label
    validationActions: [Deny]
    matchResources:
      objectSelector:
        matchLabels:
          kubernetes.io/metadata.name: cnti-testsuite
  YAML

def with_admission_policy(yaml : String, &)
  path = "/tmp/cnti-spec-policy-#{Process.pid}.yml"
  File.write(path, yaml)
  begin
    ShellCmd.run("kubectl apply -f #{path}", force_output: true)[:status].success?.should be_true
    # The policy takes a moment to be served.
    sleep 3.seconds
    yield
  ensure
    ShellCmd.run("kubectl delete -f #{path} --ignore-not-found", force_output: true)
    File.delete?(path)
  end
end

# Back to privileged on the suite's namespace. The API server keeps enforcing
# a deleted admission policy for a moment, so the label is retried until the
# denial is gone; that also leaves the next spec a cluster without it. A saved
# level goes too, so a reused namespace isn't put back to baseline on release.
def restore_privileged_label
  repeat_with_timeout(timeout: 60, errormsg: "namespace #{TESTSUITE_NAMESPACE} could not be set back to privileged", delay: 2) do
    ShellCmd.run("kubectl label namespace #{TESTSUITE_NAMESPACE} pod-security.kubernetes.io/enforce=privileged --overwrite", force_output: true)[:status].success?
  end
  ShellCmd.run("kubectl annotate namespace #{TESTSUITE_NAMESPACE} #{SuiteNamespaces::PREVIOUS_ENFORCE}-", force_output: true)
end

describe "Cluster Setup" do
  it "'install_cluster_tools' should stop the run with the cluster's reason when the helper pods are refused", tags: ["cluster_setup"] do
    ShellCmd.run_testsuite("setup:create_namespace")[:status].success?.should be_true
    with_admission_policy(DENY_CLUSTER_TOOLS_PODS) do
      result = ShellCmd.run_testsuite("setup:install_cluster_tools", cmd_prefix: "CNTI_TESTSUITE_CLUSTER_TOOLS_TIMEOUT=30")
      result[:status].exit_code.should eq(1)
      (/cluster-tools did not become ready within 30s: 0 of \d+ pod\(s\) ready/ =~ result[:output]).should_not be_nil
      # The cluster's own explanation, from the DaemonSet's events.
      (/cnti spec: cluster-tools pods are denied here/ =~ result[:output]).should_not be_nil
      (/admission policy that refuses them/ =~ result[:output]).should_not be_nil
    end
  ensure
    result = ShellCmd.run_testsuite("setup:uninstall_cluster_tools")
  end

  it "'setup' should stop with the reason when the cluster refuses the privileged Pod Security label", tags: ["cluster_setup"] do
    ShellCmd.run_testsuite("setup:create_namespace")[:status].success?.should be_true
    # A namespace already at privileged is left alone; take it down a level
    # first, so the suite has a label to set.
    ShellCmd.run("kubectl label namespace #{TESTSUITE_NAMESPACE} pod-security.kubernetes.io/enforce=baseline --overwrite", force_output: true)[:status].success?.should be_true
    with_admission_policy(DENY_PRIVILEGED_LABEL) do
      result = ShellCmd.run_testsuite("setup:create_namespace")
      result[:status].exit_code.should eq(1)
      (/Pod Security: the suite could not set pod-security.kubernetes.io\/enforce=privileged on namespace cnti-testsuite: .*cnti spec: privileged namespaces are denied here/ =~ result[:output]).should_not be_nil
      (/Have a user allowed to change Pod Security labels/ =~ result[:output]).should_not be_nil
    end
  ensure
    restore_privileged_label
  end

  it "'setup' should leave a namespace that already enforces privileged untouched", tags: ["cluster_setup"] do
    ShellCmd.run_testsuite("setup:create_namespace")
    restore_privileged_label
    with_admission_policy(DENY_PRIVILEGED_LABEL) do
      # The namespace is already privileged: no label write, so the policy is never met.
      result = ShellCmd.run_testsuite("setup:create_namespace")
      result[:status].success?.should be_true
    end
  end

  it "'install_cluster_tools' should create the cnti-testsuite namespace when it is missing", tags: ["cluster_setup"] do
    KubectlClient::Delete.resource("namespace", ClusterTools.namespace, extra_opts: "--ignore-not-found --wait")

    result = ShellCmd.run_testsuite("setup:install_cluster_tools")
    result[:status].success?.should be_true
    SuiteNamespaces.owned?(KubectlClient::Get.resource("namespace", ClusterTools.namespace)).should be_true
  ensure
    result = ShellCmd.run_testsuite("setup:uninstall_cluster_tools")
    result[:status].success?.should be_true
  end
end
