require "../spec_helper"
require "json"
require "../../src/tasks/utils/pod_security.cr"

# Pure unit specs for the Pod Security helpers, without a cluster: what is sent
# to the dry run, how pods are grouped, and how a dry run's output is read.

def live_pod(name = "app-7d9f-abcde", image = "busybox:1.36", owner = "ReplicaSet", owner_name = "app-7d9f", controller = true)
  JSON.parse({
    "apiVersion" => "v1", "kind" => "Pod",
    "metadata"   => {
      "name" => name, "namespace" => "cnf", "uid" => "1234", "resourceVersion" => "42",
      "labels"          => {"app" => "app"},
      "annotations"     => {"container.apparmor.security.beta.kubernetes.io/app" => "unconfined"},
      "ownerReferences" => [{"kind" => owner, "name" => owner_name, "controller" => controller}],
    },
    "spec" => {
      "nodeName" => "node-1", "serviceAccountName" => "app-sa", "serviceAccount" => "app-sa", "priority" => 0,
      "containers" => [{"name" => "app", "image" => image,
                        "volumeMounts" => [{"name" => "data", "mountPath" => "/data"},
                                           {"name" => "kube-api-access-x1y2z", "mountPath" => "/var/run/secrets/kubernetes.io/serviceaccount"}]}],
      "initContainers" => [{"name" => "init", "image" => image,
                            "volumeMounts" => [{"name" => "kube-api-access-x1y2z", "mountPath" => "/var/run/secrets/kubernetes.io/serviceaccount"}]}],
      "ephemeralContainers" => [{"name" => "debugger", "image" => image}],
      "volumes" => [{"name" => "data", "emptyDir" => {} of String => String},
                    {"name" => "kube-api-access-x1y2z", "projected" => {"sources" => [] of String}}],
    },
    "status" => {"phase" => "Running"},
  }.to_json)
end

describe "PodSecurity" do
  describe "dry_run_pod" do
    it "keeps name, labels and annotations, and drops what belongs to the live object", tags: ["points"] do
      sent = PodSecurity.dry_run_pod(live_pod)
      sent["metadata"].as_h.keys.sort.should eq(["annotations", "labels", "name"])
      # Baseline reads AppArmor from these annotations on clusters that do not
      # mirror them into appArmorProfile.
      sent.dig("metadata", "annotations", "container.apparmor.security.beta.kubernetes.io/app").as_s.should eq("unconfined")
      sent["status"]?.should be_nil
    end

    it "drops the service account, its token volume and mounts, the node and the priority", tags: ["points"] do
      spec = PodSecurity.dry_run_pod(live_pod)["spec"]
      ["nodeName", "serviceAccountName", "serviceAccount", "priority", "ephemeralContainers"].each do |field|
        spec[field]?.should be_nil
      end
      spec["volumes"].as_a.map { |v| v["name"].as_s }.should eq(["data"])
      spec.dig("containers", 0, "volumeMounts").as_a.map { |m| m["name"].as_s }.should eq(["data"])
      spec.dig("initContainers", 0, "volumeMounts").as_a.should be_empty
    end
  end

  describe "owner and variant_key" do
    it "names the controller, or the pod itself when it has none", tags: ["points"] do
      PodSecurity.owner(live_pod).should eq("ReplicaSet/app-7d9f")
      PodSecurity.owner(live_pod(name: "bare", controller: false)).should eq("Pod/bare")
    end

    it "groups replicas of one owner, and keeps pods that differ apart", tags: ["points"] do
      replica_a = PodSecurity.variant_key(live_pod(name: "app-7d9f-aaaaa"))
      replica_b = PodSecurity.variant_key(live_pod(name: "app-7d9f-bbbbb"))
      new_image = PodSecurity.variant_key(live_pod(name: "app-7d9f-ccccc", image: "busybox:1.37"))
      other_owner = PodSecurity.variant_key(live_pod(name: "x-1", owner_name: "other-5c4b"))
      # The pod name is part of what is sent, not of the key.
      replica_a.should eq(replica_b)
      new_image.should_not eq(replica_a)
      other_owner.should_not eq(replica_a)
    end
  end

  describe "canary" do
    it "is a pod baseline forbids", tags: ["points"] do
      PodSecurity.canary_pod.dig("spec", "hostPID").as_bool.should be_true
    end

    it "lets the test go on only when Pod Security rejects the canary", tags: ["points"] do
      rejected = %(Error from server (Forbidden): error when creating "STDIN": pods "cnti-pss-canary" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostPID=true)\n)
      PodSecurity.canary_skip_reason(false, rejected).should be_nil
      PodSecurity.canary_skip_reason(true, "pod/cnti-pss-canary created (server dry run)\n").not_nil!.should contain("is not enforcing baseline")
      webhook = %(Error from server (Forbidden): admission webhook "validate.kyverno.svc-fail" denied the request\n)
      PodSecurity.canary_skip_reason(false, webhook).not_nil!.should contain("could not confirm")
    end
  end

  describe "verdict" do
    it "passes a dry run that was admitted", tags: ["points"] do
      PodSecurity.verdict(true, "pod/app created (server dry run)\n").should eq({PodSecurity::Verdict::Passed, nil})
    end

    it "reads Pod Security's rejection as a violation, with its reason", tags: ["points"] do
      output = %(Error from server (Forbidden): error when creating "STDIN": pods "caps" is forbidden: violates PodSecurity "baseline:latest": non-default capabilities (container "c" must not include "NET_ADMIN" in securityContext.capabilities.add)\n)
      verdict, reason = PodSecurity.verdict(false, output)
      verdict.should eq(PodSecurity::Verdict::Violation)
      reason.should eq(%(non-default capabilities (container "c" must not include "NET_ADMIN" in securityContext.capabilities.add)))
    end

    it "leaves a rejection by anything else not judged, with the reason", tags: ["points"] do
      webhook = %(Error from server (Forbidden): error when creating "STDIN": admission webhook "validate.kyverno.svc-fail" denied the request: policy require-labels\n)
      verdict, reason = PodSecurity.verdict(false, webhook)
      verdict.should eq(PodSecurity::Verdict::NotJudged)
      reason.not_nil!.should start_with(%(error when creating "STDIN": admission webhook "validate.kyverno.svc-fail" denied the request))

      verdict, reason = PodSecurity.verdict(false, "")
      verdict.should eq(PodSecurity::Verdict::NotJudged)
      reason.should eq("the dry run failed without a message")
    end
  end
end
