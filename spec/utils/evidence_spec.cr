require "../spec_helper"
require "./schema_validator"
require "../../src/tasks/**"

# The evidence bundle: the badge and the in-toto statement derived from a
# results file. Needs no cluster. The badge fixtures were written by the
# badge script of testsuite-action v1.2.0 with the same inputs, so the SVG and
# the shields JSON the suite writes are byte for byte what projects publish
# today.
describe "Evidence" do
  fixture = "spec/fixtures/results-sample.yml"

  it "names the test set on the badge: essential for cert, the task otherwise", tags: ["points"] do
    Evidence.label_set("cert").should eq("essential")
    Evidence.label_set("workload").should eq("workload")
    Evidence.label_set("security").should eq("security")
  end

  it "reads the task, the status and the score from the results file", tags: ["points"] do
    results = YAML.parse(File.read(fixture))
    Evidence.task_of(results).should eq("cert")
    Evidence.task_of(YAML.parse(%(command: /opt/cnti-testsuite workload --output json))).should eq("workload")
    Evidence.task_of(YAML.parse(%(name: x))).should eq("cert")
    Evidence.status_of(results).should eq("failed")
    Evidence.message_of(results).should eq("1/3")
  end

  it "writes the badge the action and the component published before it existed", tags: ["points"] do
    svg = Evidence.badge_svg("essential", "1/3", "failed")
    svg.strip.should eq(File.read("spec/fixtures/cnti-badge-essential-1-3-failed.svg").strip)

    json = JSON.parse(Evidence.badge_json("essential", "1/3", "failed"))
    expected = JSON.parse(File.read("spec/fixtures/cnti-badge-essential-1-3-failed.json"))
    json.should eq(expected)

    JSON.parse(Evidence.badge_json("essential", "17/19", "passed"))["color"].as_s.should eq("brightgreen")
    Evidence.badge_svg("essential", "17/19", "passed").should contain(%(fill="#4c1"))
    Evidence.badge_svg("essential", "17/19", "error").should contain(%(fill="#9f9f9f"))
    Evidence.badge_svg("workload", "51/57", "failed").should contain(%(aria-label="CNTi workload: 51/57"))
  end

  it "writes an in-toto Test Result statement about the results file", tags: ["points"] do
    doc = JSON.parse(Evidence.statement(fixture, YAML.parse(File.read(fixture))))
    doc["_type"].as_s.should eq("https://in-toto.io/Statement/v1")
    doc["predicateType"].as_s.should eq("https://in-toto.io/attestation/test-result/v0.1")
    doc["subject"][0]["name"].as_s.should eq("results-sample.yml")
    doc["subject"][0]["digest"]["sha256"].as_s.should eq(Digest::SHA256.hexdigest(File.read(fixture)))

    predicate = doc["predicate"]
    predicate["result"].as_s.should eq("FAILED")
    predicate["passedTests"].as_a.map(&.as_s).should eq(["liveness", "not_a_test"])
    predicate["failedTests"].as_a.map(&.as_s).should eq(["privileged_containers"])

    cnti = predicate["cnti"]
    cnti["task"].as_s.should eq("cert")
    cnti["label"].as_s.should eq("CNTi essential")
    cnti["status"].as_s.should eq("failed")
    cnti["exit_code"].as_i.should eq(1)
    cnti["passed"].as_i.should eq(1)
    cnti["max_passed"].as_i.should eq(3)
    cnti["essential_passed"].as_i.should eq(1)
    cnti["criteria"]["cert"]["passed"].as_bool.should be_false
    cnti["self_published"].as_bool.should be_true
    cnti["testsuite_version"].as_s.should eq("v2.0.0")
  end

  it "statement conforms to docs/cnti-evidence.schema.json", tags: ["points"] do
    schema = JSON.parse(File.read("docs/cnti-evidence.schema.json"))
    statement = YAML.parse(Evidence.statement(fixture, YAML.parse(File.read(fixture))))
    validate_against_schema(statement, schema, schema["$defs"])
  end

  it "refuses a results file without a verdict", tags: ["points"] do
    dir = File.tempname("cnti-evidence-running")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "cnti-testsuite-results-20261010-120000-000.yml")
      File.write(path, "name: cnti testsuite\nstatus: running\nexit_code:\nitems: []\n")
      expect_raises(ArgumentError, /did not finish/) { Evidence.write(path, File.join(dir, "out")) }
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "'evidence' writes the bundle for a results file into the output directory", tags: ["points"] do
    dir = File.tempname("cnti-evidence")
    begin
      result = ShellCmd.run_testsuite("evidence --results-file #{fixture} --output-dir #{dir}")
      result[:status].success?.should be_true
      result[:output].should contain("Evidence: #{dir}")
      ["cnti-badge.svg", "cnti-badge.json", "cnti-evidence.json", "results-sample.yml", "results-sample.xml"].each do |name|
        File.exists?(File.join(dir, name)).should be_true
      end
      JSON.parse(File.read(File.join(dir, "cnti-badge.json")))["label"].as_s.should eq("CNTi essential")
      statement = JSON.parse(File.read(File.join(dir, "cnti-evidence.json")))
      statement["predicate"]["cnti"]["results_file"].as_s.should eq("results-sample.yml")
      # The copy is the subject: same bytes, same digest.
      Digest::SHA256.hexdigest(File.read(File.join(dir, "results-sample.yml"))).should eq(statement["subject"][0]["digest"]["sha256"].as_s)
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "'evidence' rejects a missing results file as a usage error", tags: ["points"] do
    result = ShellCmd.run_testsuite("evidence --results-file /nonexistent/results.yml")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("No results file")
  end
end
