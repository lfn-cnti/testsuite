require "../spec_helper"
require "../../src/tasks/utils/kubescape.cr"

# In-process, no cluster: the parser keeps the fields kubescape names and the
# reasons built from them.
private RESPONSE = <<-JSON
{
  "name": "Ensure CPU limits are set",
  "remediation": "Set resources.limits.cpu for every container.",
  "ruleReports": [{
    "name": "resources-cpu-limits",
    "ruleResponses": [{
      "alertMessage": "",
      "alertObject": {"k8sApiObjects": [{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": {"name": "web", "namespace": "shop"}}]},
      "failedPaths": null,
      "reviewPaths": null,
      "fixPaths": [
        {"path": "spec.template.spec.containers[0].resources.limits.cpu", "value": "YOUR_VALUE"},
        {"path": "spec.template.spec.securityContext.runAsNonRoot", "value": "true"}
      ]
    }, {
      "alertMessage": "hostPath volume is mounted",
      "alertObject": {"k8sApiObjects": [{"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "tool", "namespace": "shop"}}]},
      "failedPaths": ["spec.volumes[0].hostPath"],
      "reviewPaths": null,
      "fixPaths": null
    }]
  }]
}
JSON

describe "Kubescape report parsing" do
  it "keeps the failed fields and suggested values, and phrases them", tags: ["points"] do
    report = Kubescape.parse_test_report(JSON.parse(RESPONSE))
    report.remediation.should eq("Set resources.limits.cpu for every container.")
    report.failed_resources.size.should eq(2)

    web = report.failed_resources[0]
    web.kind.should eq("Deployment")
    web.paths.should eq(["spec.template.spec.containers[0].resources.limits.cpu", "spec.template.spec.securityContext.runAsNonRoot"])
    web.reason_for("spec.template.spec.containers[0].resources.limits.cpu").should eq("spec.template.spec.containers[0].resources.limits.cpu is not set")
    web.reason_for("spec.template.spec.securityContext.runAsNonRoot").should eq("spec.template.spec.securityContext.runAsNonRoot should be true")

    tool = report.failed_resources[1]
    tool.paths.should eq(["spec.volumes[0].hostPath"])
    tool.reason_for("spec.volumes[0].hostPath").should eq("spec.volumes[0].hostPath")
    tool.alert_message.should eq("hostPath volume is mounted")
  end

  it "records the finding once per container when the test names it", tags: ["points"] do
    report = Kubescape.parse_test_report(JSON.parse(RESPONSE))
    result = CNFManager::TestCaseResult.empty
    Kubescape.report_failed_resources(report, result, finding: "no hardening is defined")
    result.result_impacted_resources.map { |e| e["reason"] }.uniq.should eq(["no hardening is defined"])
    result.result_impacted_resources.map { |e| e["name"] }.uniq.should eq(["web", "tool"])
    result.result_impacted_resources.none? { |e| e["reason"].to_s.includes?("spec.") }.should be_true
  end

  it "records one impacted entry per failed field", tags: ["points"] do
    report = Kubescape.parse_test_report(JSON.parse(RESPONSE))
    result = CNFManager::TestCaseResult.empty
    Kubescape.report_failed_resources(report, result)
    reasons = result.result_impacted_resources.map { |e| e["reason"] }
    reasons.should eq([
      "spec.template.spec.containers[0].resources.limits.cpu is not set",
      "spec.template.spec.securityContext.runAsNonRoot should be true",
      "spec.volumes[0].hostPath",
    ])
    result.result_impacted_resources.map { |e| e["name"] }.should eq(["web", "web", "tool"])
  end

  it "names the variables that hold a credential and leaves out plain switches", tags: ["points"] do
    object = JSON.parse(<<-JSON)
    {
      "spec": {"template": {"spec": {"containers": [{
        "name": "mongodb",
        "env": [
          {"name": "BITNAMI_DEBUG", "value": "false"},
          {"name": "ALLOW_EMPTY_PASSWORD", "value": "yes"},
          {"name": "MONGODB_ROOT_PASSWORD", "value": "hunter2"}
        ]
      }]}}}
    }
    JSON
    paths = [
      "spec.template.spec.containers[0].env[1].name",
      "spec.template.spec.containers[0].env[1].value",
      "spec.template.spec.containers[0].env[2].name",
      "spec.template.spec.containers[0].env[2].value",
    ]
    credentials = Kubescape.credential_findings(object, paths)
    credentials[:switches].should eq(["environment variable ALLOW_EMPTY_PASSWORD of container mongodb"])
    credentials[:findings].should eq([
      {container: "mongodb", reason: "environment variable MONGODB_ROOT_PASSWORD holds a value (spec.template.spec.containers[0].env[2])"},
    ])
    credentials[:findings].none? { |f| f[:reason].includes?("hunter2") }.should be_true
  end

  it "keeps a variable the scanner names when the object does not have it", tags: ["points"] do
    object = JSON.parse(%({"spec": {"template": {"spec": {"containers": [{"name": "app", "env": []}]}}}}))
    paths = ["spec.template.spec.containers[0].env[3].name", "spec.template.spec.containers[0].env[3].value"]
    Kubescape.credential_findings(object, paths)[:findings].map { |f| f[:reason] }.should eq(paths)
  end

  it "reads ConfigMap keys and keeps a path it cannot resolve", tags: ["points"] do
    object = JSON.parse(%({"data": {"db_password": "hunter2", "use_password": "true"}}))
    credentials = Kubescape.credential_findings(object, ["data[db_password]", "data[use_password]", "data[gone]"])
    credentials[:switches].should eq(["key use_password"])
    credentials[:findings].map { |f| f[:reason] }.should eq(["key db_password holds a value (data[db_password])", "data[gone]"])
    Kubescape.credential_findings(nil, ["spec.containers[0].env[0].name"])[:findings].map { |f| f[:reason] }.should eq(["spec.containers[0].env[0].name"])
  end
end
