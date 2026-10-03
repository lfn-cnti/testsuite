require "../spec_helper"
require "json"
require "../../src/tasks/utils/disruption_budget.cr"

# Pure unit specs for the disruption budget decisions, without a cluster. The
# rounding and the "neither field set" cases were checked against the
# disruption controller on Kubernetes 1.37.

def db_json(value) : JSON::Any
  JSON.parse(value.to_json)
end

def db_workload(name, replicas, labels = {"app" => "a"}, pod_spec = {} of String => String, namespace = "cnf")
  DisruptionBudget::Workload.new("Deployment", name, namespace, replicas, labels, db_json(pod_spec))
end

def db_budget(name, spec, namespace = "cnf")
  DisruptionBudget::Budget.new(name, namespace, db_json(spec))
end

describe "DisruptionBudget" do
  describe "selects?" do
    it "matches matchLabels and every matchExpressions operator", tags: ["points"] do
      labels = {"app" => "a", "tier" => "web"}
      DisruptionBudget.selects?(db_json({"matchLabels" => {"app" => "a"}}), labels).should be_true
      DisruptionBudget.selects?(db_json({"matchLabels" => {"app" => "b"}}), labels).should be_false
      DisruptionBudget.selects?(db_json({"matchExpressions" => [{"key" => "tier", "operator" => "In", "values" => ["web", "db"]}]}), labels).should be_true
      DisruptionBudget.selects?(db_json({"matchExpressions" => [{"key" => "tier", "operator" => "NotIn", "values" => ["web"]}]}), labels).should be_false
      DisruptionBudget.selects?(db_json({"matchExpressions" => [{"key" => "app", "operator" => "Exists"}]}), labels).should be_true
      DisruptionBudget.selects?(db_json({"matchExpressions" => [{"key" => "app", "operator" => "DoesNotExist"}]}), labels).should be_false
    end

    it "treats an empty selector as all pods and a missing one as none", tags: ["points"] do
      DisruptionBudget.selects?(db_json({} of String => String), {"app" => "a"}).should be_true
      DisruptionBudget.selects?(nil, {"app" => "a"}).should be_false
    end
  end

  describe "allowed_evictions" do
    it "rounds percentages up, as the eviction API does", tags: ["points"] do
      DisruptionBudget.scaled(db_json("50%"), 3).should eq(2)
      DisruptionBudget.scaled(db_json("25%"), 3).should eq(1)
      DisruptionBudget.allowed_evictions(db_budget("b", {"minAvailable" => "50%"}), 3).should eq(1)
      DisruptionBudget.allowed_evictions(db_budget("b", {"maxUnavailable" => "25%"}), 3).should eq(1)
      DisruptionBudget.allowed_evictions(db_budget("b", {"maxUnavailable" => 1}), 2).should eq(1)
    end

    it "allows none for maxUnavailable 0, minAvailable equal to the pods, or neither set", tags: ["points"] do
      DisruptionBudget.allowed_evictions(db_budget("b", {"maxUnavailable" => 0}), 2).should eq(0)
      DisruptionBudget.allowed_evictions(db_budget("b", {"minAvailable" => 2}), 2).should eq(0)
      DisruptionBudget.allowed_evictions(db_budget("b", {"minAvailable" => "100%"}), 2).should eq(0)
      DisruptionBudget.allowed_evictions(db_budget("b", {"selector" => {"matchLabels" => {"app" => "a"}}}), 2).should eq(0)
    end
  end

  describe "spread" do
    it "counts a required anti-affinity or DoNotSchedule constraint only when it selects the workload's own pods", tags: ["points"] do
      own = {"matchLabels" => {"app" => "a"}}
      other = {"matchLabels" => {"app" => "other"}}
      anti = ->(sel : Hash(String, Hash(String, String))) { {"affinity" => {"podAntiAffinity" => {"requiredDuringSchedulingIgnoredDuringExecution" => [{"topologyKey" => "kubernetes.io/hostname", "labelSelector" => sel}]}}} }
      DisruptionBudget.spread(db_workload("w", 2, pod_spec: anti.call(own)))[0].should be_true
      DisruptionBudget.spread(db_workload("w", 2, pod_spec: anti.call(other)))[0].should be_false
      tsc = ->(when_unsat : String) { {"topologySpreadConstraints" => [{"topologyKey" => "kubernetes.io/hostname", "whenUnsatisfiable" => when_unsat, "labelSelector" => own}]} }
      DisruptionBudget.spread(db_workload("w", 2, pod_spec: tsc.call("DoNotSchedule")))[0].should be_true
    end

    it "does not count preferred anti-affinity or ScheduleAnyway, and names them", tags: ["points"] do
      preferred = {"affinity" => {"podAntiAffinity" => {"preferredDuringSchedulingIgnoredDuringExecution" => [{"weight" => 100, "podAffinityTerm" => {"topologyKey" => "kubernetes.io/hostname"}}]}}}
      ok, seen = DisruptionBudget.spread(db_workload("w", 2, pod_spec: preferred))
      ok.should be_false
      seen.first.should contain("preferred podAntiAffinity")
      anyway = {"topologySpreadConstraints" => [{"topologyKey" => "kubernetes.io/hostname", "whenUnsatisfiable" => "ScheduleAnyway", "labelSelector" => {"matchLabels" => {"app" => "a"}}}]}
      ok, seen = DisruptionBudget.spread(db_workload("w", 2, pod_spec: anyway))
      ok.should be_false
      seen.first.should contain("ScheduleAnyway")
    end
  end

  describe "replicas" do
    it "takes an HPA's minReplicas in the same namespace, else spec.replicas, else 1", tags: ["points"] do
      deploy = db_json({"kind" => "Deployment", "metadata" => {"name" => "w"}, "spec" => {"replicas" => 1}})
      hpa = db_json({"spec" => {"scaleTargetRef" => {"kind" => "Deployment", "name" => "w"}, "minReplicas" => 3}})
      DisruptionBudget.replicas(deploy, "cnf", [{hpa, "cnf"}]).should eq(3)
      DisruptionBudget.replicas(deploy, "cnf", [{hpa, "elsewhere"}]).should eq(1)
      DisruptionBudget.replicas(db_json({"kind" => "Deployment", "metadata" => {"name" => "w"}, "spec" => {} of String => String}), "cnf", [] of {JSON::Any, String}).should eq(1)
    end
  end

  describe "evaluate" do
    it "measures a budget against all the workloads it selects", tags: ["points"] do
      a = db_workload("a", 2, {"tier" => "web", "app" => "a"})
      b = db_workload("b", 2, {"tier" => "web", "app" => "b"})
      budget = db_budget("web", {"minAvailable" => 3, "selector" => {"matchLabels" => {"tier" => "web"}}})
      DisruptionBudget.evaluate([a, b], [budget]).details.first.should contain("allows 1 of 4 selected pod(s)")
    end

    it "names a budget that sets neither field as blocking", tags: ["points"] do
      w = db_workload("w", 1)
      budget = db_budget("bare", {"selector" => {"matchLabels" => {"app" => "a"}}})
      evaluation = DisruptionBudget.evaluate([w], [budget])
      evaluation.findings.size.should eq(1)
      evaluation.findings.first.reason.should contain("neither minAvailable nor maxUnavailable")
    end

    it "lists a budget that selects no pod of the CNF without failing it, and is N/A with nothing to judge", tags: ["points"] do
      w = db_workload("w", 1)
      evaluation = DisruptionBudget.evaluate([w], [db_budget("elsewhere", {"maxUnavailable" => 0, "selector" => {"matchLabels" => {"app" => "x"}}})])
      evaluation.findings.should be_empty
      evaluation.details.first.should contain("selects no pod of the CNF")
      DisruptionBudget.evaluate([w], [] of DisruptionBudget::Budget).applicable.should be_false
    end
  end
end
