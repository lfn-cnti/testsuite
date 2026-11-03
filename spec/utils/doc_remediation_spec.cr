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

  it "links to the documentation of the version the binary was built from", tags: ["points"] do
    ReleaseManager::DOC_REF.should_not be_empty
    DocRemediation.entry("node_drain").not_nil!.url.should eq(
      "https://github.com/lfn-cnti/testsuite/blob/#{ReleaseManager::DOC_REF}/docs/TEST_DOCUMENTATION.md#node-drain")
  end

  it "reads a test's Details without its collapsing HTML, with the common rules it links to", tags: ["points"] do
    markdown = <<-MD
    ### Sample test

    #### Overview

    Checks one thing.

    #### Remediation

    Fix it.

    #### Usage

    `./cnti-testsuite sample_test`

    #### Details

    <details>
    <summary>How the test works in detail</summary>

    * **Verdicts**: fails on the thing.
    * **Common rules**: [Shared rule](#shared-rule).

    </details>

    ----------

    ## Common rules

    Rules that several tests share.

    ----------

    ### Shared rule

    What every such test does.

    ----------

    ### Unlinked rule

    Something else.
    MD

    entry = DocRemediation.parse_entries(markdown)["sample_test"]
    entry.overview.should eq("Checks one thing.")
    entry.details.should eq("* **Verdicts**: fails on the thing.\n* **Common rules**: [Shared rule](#shared-rule).")
    entry.common_rules.map(&.heading).should eq(["Shared rule"])
    entry.common_rules[0].text.should eq("What every such test does.")
    entry.common_rules[0].url.should end_with("TEST_DOCUMENTATION.md#shared-rule")
  end

  it "gives the rollout tests their Details and the rules they share", tags: ["points"] do
    ["rolling_update", "rolling_version_change", "rolling_downgrade", "rollback"].each do |name|
      entry = DocRemediation.entry(name).not_nil!
      entry.details.not_nil!.should contain("**Verdicts**")
      entry.common_rules.map(&.heading).should eq(["Rollout tests", "Jobs and CronJobs"])
    end
    DocRemediation.entry("rolling_update").not_nil!.common_rules[0].text.should contain("version skew")
    # A test without Details keeps its documentation as before.
    DocRemediation.entry("liveness").not_nil!.details.should be_nil
  end
end
