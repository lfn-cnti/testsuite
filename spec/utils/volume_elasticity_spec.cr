require "../spec_helper"
require "../../src/tasks/utils/volume_elasticity.cr"

# In-process, no cluster: what makes a volume elastic, from the objects alone.
private def pv(spec : String, provisioner : String? = nil) : JSON::Any
  annotations = provisioner ? %({"pv.kubernetes.io/provisioned-by": "#{provisioner}"}) : "{}"
  JSON.parse(%({"metadata": {"name": "pv-1", "annotations": #{annotations}}, "spec": #{spec}}))
end

private DEFAULT_CLASS = JSON.parse(%({"metadata": {"name": "standard", "annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}))
private OTHER_CLASS   = JSON.parse(%({"metadata": {"name": "fast"}}))

private LOCAL_PATH = %({"storageClassName": "standard", "hostPath": {"path": "/var/local-path-provisioner/pvc-1"},
  "nodeAffinity": {"required": {"nodeSelectorTerms": [{"matchExpressions": [{"key": "kubernetes.io/hostname", "operator": "In", "values": ["worker"]}]}]}}})
private CLOUD_DISK = %({"storageClassName": "gp3", "csi": {"driver": "ebs.csi.aws.com"},
  "nodeAffinity": {"required": {"nodeSelectorTerms": [{"matchExpressions": [{"key": "topology.ebs.csi.aws.com/zone", "operator": "In", "values": ["eu-north-1a"]}]}]}}})

describe "VolumeElasticity" do
  it "takes a volume bound to a zone for elastic, whatever its provisioner is called", tags: ["points"] do
    volume = pv(CLOUD_DISK, "ebs.csi.aws.com")
    VolumeElasticity.node_bound_reason(volume).should be_nil
    judgement = VolumeElasticity.judge(volume, OTHER_CLASS)
    judgement[:verdict].should eq(VolumeElasticity::Verdict::Elastic)
    judgement[:reason].should eq("not tied to a node, provisioned by ebs.csi.aws.com (storage class gp3)")
  end

  it "finds local, hostPath and node-pinned volumes", tags: ["points"] do
    VolumeElasticity.node_bound_reason(pv(%({"local": {"path": "/var/tmp"}}))).should eq("a local volume at /var/tmp")
    VolumeElasticity.node_bound_reason(pv(%({"hostPath": {"path": "/data"}}))).should eq("a hostPath volume at /data")
    pinned = %({"csi": {"driver": "x"}, "nodeAffinity": {"required": {"nodeSelectorTerms": [{"matchFields": [{"key": "metadata.name", "operator": "In", "values": ["node-1"]}]}]}}})
    VolumeElasticity.node_bound_reason(pv(pinned)).should eq("pinned to node node-1")
  end

  it "does not hold the cluster's default storage class against the CNF", tags: ["points"] do
    volume = pv(LOCAL_PATH, "rancher.io/local-path")
    VolumeElasticity.judge(volume, DEFAULT_CLASS)[:verdict].should eq(VolumeElasticity::Verdict::ClusterChoice)
    # a class the CNF chose, or a volume made by hand, is the CNF's finding
    VolumeElasticity.judge(volume, OTHER_CLASS)[:verdict].should eq(VolumeElasticity::Verdict::NodeBound)
    VolumeElasticity.judge(volume, nil)[:verdict].should eq(VolumeElasticity::Verdict::NodeBound)
    VolumeElasticity.judge(pv(LOCAL_PATH), DEFAULT_CLASS)[:verdict].should eq(VolumeElasticity::Verdict::NodeBound)
  end

  it "names the claims of pod volumes and of volumeClaimTemplates", tags: ["points"] do
    deployment = JSON.parse(%({"metadata": {"name": "web"}, "spec": {"template": {"spec": {"volumes": [
      {"name": "config", "configMap": {"name": "c"}}, {"name": "data", "persistentVolumeClaim": {"claimName": "web-data"}}]}}}}))
    VolumeElasticity.claim_names(deployment).should eq(["web-data"])
    statefulset = JSON.parse(%({"metadata": {"name": "db"}, "spec": {"replicas": 2, "volumeClaimTemplates": [{"metadata": {"name": "data"}}],
      "template": {"spec": {"containers": []}}}}))
    VolumeElasticity.claim_names(statefulset).should eq(["data-db-0", "data-db-1"])
  end
end
