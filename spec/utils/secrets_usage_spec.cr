require "../spec_helper"
require "../../src/tasks/**"

describe "SecretsUsage" do
  pod_spec = JSON.parse(%({
    "imagePullSecrets": [{"name": "regcred"}],
    "volumes": [
      {"name": "certs", "secret": {"secretName": "db-tls"}},
      {"name": "unmounted", "secret": {"secretName": "db-extra"}},
      {"name": "proj", "projected": {"sources": [{"secret": {"name": "db-ca", "optional": true}}]}}
    ],
    "initContainers": [{"name": "init", "volumeMounts": [{"name": "proj", "mountPath": "/p"}]}],
    "containers": [{
      "name": "db",
      "volumeMounts": [{"name": "certs", "mountPath": "/certs"}],
      "env": [
        {"name": "PASSWORD", "valueFrom": {"secretKeyRef": {"name": "db-password", "key": "password"}}},
        {"name": "PLAIN", "value": "x"}
      ],
      "envFrom": [{"secretRef": {"name": "db-env"}}, {"configMapRef": {"name": "cm"}}]
    }]
  }))

  it "lists every Secret a pod spec reads, a volume only when mounted", tags: ["points"] do
    refs = SecretsUsage.references(pod_spec)
    refs.map(&.name).should eq(["db-tls", "db-ca", "db-password", "db-env", "regcred"])
    refs.find { |r| r.name == "db-tls" }.not_nil!.where.should eq("volume certs")
    refs.find { |r| r.name == "db-password" }.not_nil!.where.should eq("env PASSWORD of container db")
    refs.find { |r| r.name == "db-ca" }.not_nil!.optional.should be_true
    refs.find { |r| r.name == "regcred" }.not_nil!.optional.should be_true
    refs.map(&.name).should_not contain("db-extra")
  end

  it "ships every Secret but the cluster's and the tooling's own", tags: ["points"] do
    secrets = [
      {metadata: {name: "db-password"}, type: "Opaque"},
      {metadata: {name: "db-tls"}, type: "kubernetes.io/tls"},
      {metadata: {name: "sh.helm.release.v1.db.v1"}, type: "helm.sh/release.v1"},
      {metadata: {name: "default-token-abc"}, type: "kubernetes.io/service-account-token"},
      {metadata: {name: "regcred"}, type: "kubernetes.io/dockerconfigjson"},
    ].map { |s| JSON.parse(s.to_json) }
    SecretsUsage.shipped(secrets).should eq(["db-password", "db-tls"])
  end

  it "names the shipped Secrets nothing reads and the required references nothing answers", tags: ["points"] do
    refs = SecretsUsage.references(pod_spec)
    SecretsUsage.unused(["db-password", "db-tls", "db-extra"], refs).should eq(["db-extra"])
    missing = SecretsUsage.missing(["db-password", "db-tls", "regcred"], refs)
    missing.map(&.name).should eq(["db-env"])
  end

  it "finds the pod spec of each workload kind", tags: ["points"] do
    SecretsUsage.pod_spec_of(JSON.parse(%({"kind": "Pod", "spec": {"containers": []}}))).should_not be_nil
    SecretsUsage.pod_spec_of(JSON.parse(%({"kind": "Deployment", "spec": {"template": {"spec": {"containers": []}}}}))).should_not be_nil
    SecretsUsage.pod_spec_of(JSON.parse(%({"kind": "CronJob", "spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": []}}}}}}))).should_not be_nil
    SecretsUsage.pod_spec_of(JSON.parse(%({"kind": "Service", "spec": {}}))).should be_nil
  end
end
