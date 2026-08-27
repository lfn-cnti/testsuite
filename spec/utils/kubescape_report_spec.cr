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
end
