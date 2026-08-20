require "./../spec_helper"
require "../../src/tasks/**"

# A test's category, type and scoring are declared at the test itself, so most
# of what used to need guarding is now enforced by the compiler: a test cannot
# be tagged for a category that never runs it, cannot be scored without
# existing, and cannot omit its type. What remains are the few invariants that
# span a test's declaration and something outside it.
describe "test metadata" do
  it "registers a task for every declared test", tags: ["points"] do
    paths = Sam.root_namespace.all_tasks.map(&.name)
    orphans = CNFManager::TestRegistry.names.reject { |name| paths.includes?(name) }
    orphans.should eq([] of String), "declared as tests but not registered as tasks: #{orphans}"
  end

  it "runs every declared test from exactly one category", tags: ["points"] do
    # A test that no category runs only executes if invoked by name. That is how
    # zombie_handled came to be run by cert but not by workload, and how
    # smf_upf_heartbeat declared itself a 5G test the 5g suite skipped. More
    # than one category would make the derived category tag ambiguous.
    #
    # clusterapi_enabled is deliberately outside every suite: poc-gated and only
    # meaningful when invoked by name. Listing it documents that as a decision
    # rather than letting any orphan through unnoticed.
    deliberate_orphans = ["clusterapi_enabled"]

    counts = Hash(String, Int32).new(0)
    CNFManager::TestRegistry::CATEGORY_AGGREGATES.each do |path|
      aggregate = Sam.root_namespace.all_tasks.find { |task| task.path == path }
      aggregate.should_not be_nil, "no aggregate task for category '#{path}'"
      deps = aggregate.not_nil!.dependency_names
      deps.empty?.should be_false, "the '#{path}' category has no members"
      deps.each { |dep| counts[dep.rpartition(":")[2]] += 1 }
    end

    # A test need not be in a category - platform:k8s_conformance is a direct member of
    # the platform suite - but something must run it.
    reachable = Set(String).new
    Sam.root_namespace.all_tasks.each do |task|
      task.dependency_names.each { |dep| reachable << dep.rpartition(":")[2] }
    end

    orphans = CNFManager::TestRegistry.names.reject { |name|
      reachable.includes?(name) || deliberate_orphans.includes?(name)
    }
    orphans.should eq([] of String), "declared tests that nothing runs: #{orphans}"

    ambiguous = counts.select { |_, n| n > 1 }.keys
    ambiguous.should eq([] of String), "tests claimed by more than one category: #{ambiguous}"
  end

  it "keeps the pre-namespace names working, exclusions included", tags: ["points"] do
    paths = Sam.root_namespace.all_tasks.map(&.path)
    {"k8s_conformance" => "platform:k8s_conformance",
     "clusterapi_enabled" => "platform:clusterapi_enabled"}.each do |old_name, new_name|
      paths.should contain(old_name)
      paths.should contain(new_name)

      # SAM matches an exclusion against a task's own path, so without rewriting
      # `~k8s_conformance` would match the alias and silently exclude nothing.
      TaskAliases.resolve_exclusions(["platform", "~#{old_name}"])
        .should eq(["platform", "~#{new_name}"])
    end

    # An alias is not a test. The registry keys on a task's name, so if the
    # top-level alias had registered it would have overwritten the real entry -
    # and, being outside the namespace, would have recorded it as a workload
    # test. Platform scope proves the real registration survived.
    CNFManager::TestRegistry["k8s_conformance"]?.not_nil!.scope.platform?.should be_true
    CNFManager::TestRegistry["clusterapi_enabled"]?.not_nil!.scope.platform?.should be_true
  end

  it "derives a test's scope from the namespace it registers in", tags: ["points"] do
    # Declaring the scope as well as choosing where to define the task meant the
    # two could disagree, and did: verify_secrets_encryption sat outside its
    # namespace block while claiming to be a platform test.
    CNFManager::TestRegistry["cluster_admin"]?.not_nil!.scope.platform?.should be_true
    CNFManager::TestRegistry["liveness"]?.not_nil!.scope.workload?.should be_true
  end

  it "derives a test's category from the aggregate that runs it", tags: ["points"] do
    CNFManager::TestRegistry.category_of["liveness"]?.should eq("resilience")
    CNFManager::TestRegistry.category_of["cluster_admin"]?.should eq("platform:security")
  end

  it "scores a test from its declared type", tags: ["points"] do
    CNFManager::Points.task_points("liveness").should eq(100)          # essential
    CNFManager::Points.task_points("reasonable_image_size").should eq(5) # normal
    CNFManager::Points.task_points("liveness", CNFManager::ResultStatus::Failed).should eq(0)
  end

  it "derives the tag vocabulary the rest of the suite reads", tags: ["points"] do
    tags = CNFManager::Points.tags_by_task("liveness")
    tags.should contain("resilience")
    tags.should contain("workload")
    tags.should contain("essential")
    tags.should contain("cert")

    platform_tags = CNFManager::Points.tags_by_task("cluster_admin")
    platform_tags.should contain("platform")
    platform_tags.should contain("platform:security")
    platform_tags.should_not contain("workload")
  end

  it "keeps every essential test in the certification set", tags: ["points"] do
    essential = CNFManager::Points.tasks_by_tag("essential").sort
    cert = CNFManager::Points.tasks_by_tag("cert").sort
    cert.should eq(essential)
  end
end
