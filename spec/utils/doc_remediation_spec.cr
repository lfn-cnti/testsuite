require "../spec_helper"
require "../../src/tasks/**"

# In-process: the documentation's Remediation sections are the fallback for
# every failed test, so every essential test must have one, and the lookup
# must resolve namespaced usage lines to bare task names.
describe "DocRemediation" do
  it "documents a remediation for every essential test", tags: ["points"] do
    essentials = CNFManager::TestRegistry.all.select { |_, m| m.type.essential? }.keys
    essentials.size.should be >= 19
    missing = essentials.reject { |name| DocRemediation.for(name) }
    missing.should eq([] of String)

    DocRemediation.for("liveness").not_nil!.should contain("Liveness Probe")
    # Namespaced usage lines are looked up by task name.
    DocRemediation.for("any:node_drain").should eq(DocRemediation.for("node_drain"))
    DocRemediation.for("no_such_test").should be_nil
  end
end
