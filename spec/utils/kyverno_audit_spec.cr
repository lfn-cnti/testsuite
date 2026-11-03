require "../spec_helper"

# In-process: what the Kyverno tests read from the CLI's output (#2891).
describe "Kyverno::PolicyAudit.failures_from" do
  it "raises AuditError, with what the CLI said, when it printed no policy report", tags: ["points"] do
    ex = expect_raises(Kyverno::AuditError) do
      Kyverno::PolicyAudit.failures_from("", exit_code: 1, stderr: "Error: failed to load policies\n")
    end
    ex.message.to_s.should contain("printed no policy report (exit code 1): Error: failed to load policies")
  end

  it "has no failures when the CLI printed no report, exited 0 and wrote no errors: nothing matched", tags: ["points"] do
    # What Kyverno 1.19.2 prints for a policy no resource matches.
    output = "Warning: pol.yaml: kyverno.io/v1 ClusterPolicy is deprecated and will be removed in a future release\n"
    Kyverno::PolicyAudit.failures_from(output, exit_code: 0).should be_empty
  end

  it "raises AuditError when the CLI printed no report but the cluster could not be reached", tags: ["points"] do
    stderr = %(E1103 22:04:03.562684  593017 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: connect: connection refused"\n)
    ex = expect_raises(Kyverno::AuditError) { Kyverno::PolicyAudit.failures_from("", exit_code: 0, stderr: stderr) }
    ex.message.to_s.should contain("connection refused")
  end

  it "has no failures in a report without results, as when nothing matched the policy", tags: ["points"] do
    output = "Applying 1 policy rule(s) to 0 resource(s)...\napiVersion: wgpolicyk8s.io/v1alpha2\nkind: ClusterPolicyReport\nmetadata:\n  name: merged\nsummary:\n  pass: 0\n"
    Kyverno::PolicyAudit.failures_from(output).should be_empty
  end

  it "reads the failed resources of a report, leaving out the excluded namespaces", tags: ["points"] do
    output = <<-YAML
      apiVersion: wgpolicyk8s.io/v1alpha2
      kind: ClusterPolicyReport
      results:
      - result: fail
        message: CRI socket mounts are not allowed
        resources:
        - {kind: Pod, name: cnf-1, namespace: cnf}
        - {kind: Pod, name: tool-1, namespace: kube-system}
      - result: pass
        message: fine
        resources:
        - {kind: Pod, name: ok-1, namespace: cnf}
      YAML
    failures = Kyverno::PolicyAudit.failures_from(output, ["kube-system"])
    failures.size.should eq(1)
    failures[0].message.should eq("CRI socket mounts are not allowed")
    failures[0].resources.map(&.name).should eq(["cnf-1"])
  end
end

private def error_report(namespace : String) : String
  <<-YAML
    apiVersion: openreports.io/v1alpha1
    kind: ClusterReport
    results:
    - result: error
      message: failed to evaluate preconditions
      resources:
      - {kind: Pod, name: x-1, namespace: #{namespace}}
    YAML
end

describe "Kyverno policy errors" do
  it "raises AuditError for an evaluation error on the CNF's own resource", tags: ["points"] do
    failures = Kyverno::PolicyAudit.failures_from(error_report("cnf"))
    failures.map(&.error).should eq([true])
    ex = expect_raises(Kyverno::AuditError) do
      Kyverno.filter_failures_for_cnf_resources(["cnf,pod/x-1"], failures)
    end
    ex.message.to_s.should contain("could not evaluate the policy for Pod/x-1 in cnf: failed to evaluate preconditions")
  end

  it "leaves out an evaluation error on a resource that is not the CNF's", tags: ["points"] do
    failures = Kyverno::PolicyAudit.failures_from(error_report("other-app"))
    Kyverno.filter_failures_for_cnf_resources(["cnf,pod/cnf-1"], failures).should be_empty
  end

  it "leaves out an evaluation error in an excluded namespace", tags: ["points"] do
    Kyverno::PolicyAudit.failures_from(error_report("kube-system"), ["kube-system"]).should be_empty
  end

  it "raises AuditError for an evaluation error that names no resource", tags: ["points"] do
    output = "apiVersion: openreports.io/v1alpha1\nkind: ClusterReport\nresults:\n- result: error\n  message: policy failed to load\n"
    ex = expect_raises(Kyverno::AuditError) { Kyverno::PolicyAudit.failures_from(output) }
    ex.message.to_s.should contain("could not evaluate the policy: policy failed to load")
  end
end

describe "Kyverno::PolicyAudit.run" do
  it "raises AuditError when the policy file is not there", tags: ["points"] do
    expect_raises(Kyverno::AuditError, /is not there/) do
      Kyverno::PolicyAudit.run("/nonexistent/kyverno/policy.yaml")
    end
  end
end
