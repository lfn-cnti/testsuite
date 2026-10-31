require "../spec_helper"
require "../../src/tasks/utils/compare"

# A results file and an expectations file with every kind of difference:
# hostpath_mounts now passes (an improvement), zombie_handled fails as
# listed, liveness isn't listed and fails (a regression), node_drain is listed
# as skipped and is n/a (changed), readiness isn't listed and passes.
private def fixtures(dir : String, expected : String) : Tuple(String, String)
  FileUtils.mkdir_p(dir)
  results = File.join(dir, "results.yml")
  File.write(results, <<-YAML)
    status: failed
    items:
      - {name: hostpath_mounts, status: passed}
      - {name: zombie_handled, status: failed}
      - {name: liveness, status: failed}
      - {name: node_drain, status: na}
      - {name: readiness, status: passed}
    YAML
  expected_file = File.join(dir, "expected.yaml")
  File.write(expected_file, expected)
  {results, expected_file}
end

COMPARE_EXPECTED = <<-YAML
  - test: hostpath_mounts
    status: failed
    reason: /sys/fs/bpf from the node is required by the non-root design
  - test: zombie_handled
    status: failed
    reason: no init in the image yet
  - test: node_drain
    status: skipped
  - test: not_run
    status: failed
  YAML

describe "Compare" do
  it "classifies every test whose result differs from the list", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      results, expected = fixtures(dir, COMPARE_EXPECTED)
      report = Compare.compare(results, expected)
      report.tests_run.should eq(5)
      report.regressions.should eq(["liveness"])
      report.improvements.should eq(["hostpath_mounts"])
      report.changed.should eq(["hostpath_mounts", "liveness", "node_drain"])
      report.changes.find! { |c| c.test == "node_drain" }.kind.should eq("changed")
      report.changes.find! { |c| c.test == "hostpath_mounts" }.reason.should contain("/sys/fs/bpf")
      report.warnings.should be_empty

      markdown = Compare.markdown(report)
      markdown.should contain("3 of the 5 compared tests differ from the file: 1 regression(s), 1 improvement(s)")
      markdown.should contain("| `hostpath_mounts` | failed | **passed** | improvement: remove its entry; listed because: /sys/fs/bpf from the node is required by the non-root design |")
      markdown.should contain("| `liveness` | passed | **failed** | regression |")
      markdown.should contain("| `node_drain` | skipped | **na** | changed |")
      markdown.should_not contain("zombie_handled")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "says when every test is as the list expects", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      results, expected = fixtures(dir, "- {test: zombie_handled, status: failed}\n- {test: liveness, status: failed}\n- {test: node_drain, status: na}\n")
      report = Compare.compare(results, expected)
      report.changes.should be_empty
      Compare.markdown(report).should contain("Every one of the 5 compared tests has the result the file expects.")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "doesn't compare a test listed without a valid status, and ignores an entry without a test", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      # A misspelled key: the test is known, its status isn't.
      results, expected = fixtures(dir, "- {test: zombie_handled, stauts: failed}\n- {test: liveness, status: broken}\n- {status: failed, reason: no test}\n- {test: node_drain, status: na}\n- {test: node_drain, status: failed}\n")
      report = Compare.compare(results, expected)
      report.uncompared.should eq(["zombie_handled", "liveness"])
      report.regressions.should be_empty
      report.changed.should be_empty
      report.warnings.any?(&.includes?("lists zombie_handled without a status of a results file")).should be_true
      report.warnings.any?(&.includes?("it has 'broken'")).should be_true
      report.warnings.any?(&.includes?("an entry without a test: it is ignored")).should be_true
      report.warnings.any?(&.includes?("lists node_drain more than once: the first entry counts")).should be_true
      markdown = Compare.markdown(report)
      markdown.should contain("Every one of the 3 compared tests has the result the file expects.")
      markdown.should contain("_Not compared: `zombie_handled`")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "lets the first entry for a test count, even when a later one has no valid status", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      results, expected = fixtures(dir, "- {test: liveness, status: failed}\n- {test: liveness, status: oops}\n- {test: zombie_handled, status: failed}\n- {test: node_drain, status: na}\n")
      report = Compare.compare(results, expected)
      report.uncompared.should be_empty
      report.changes.should be_empty
      report.warnings.should eq(["#{expected} lists liveness more than once: the first entry counts"])
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "writes the file's reasons as plain text in their cells", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      results, expected = fixtures(dir, %(- {test: node_drain, status: failed, reason: "kubectl get pods | grep x <b>[l](u)"}\n- {test: zombie_handled, status: failed}\n- {test: liveness, status: failed}\n))
      markdown = Compare.markdown(Compare.compare(results, expected))
      markdown.should contain("listed because: kubectl get pods \\| grep x &lt;b&gt;\\[l\\](u) |")
      Compare.cell(%q(!\[x\](u))).should eq(%q(!\\\[x\\\](u)))
      Compare.cell("see https://a.invalid and WWW.b.invalid").should eq(%q(see https\://a.invalid and WWW\.b.invalid))
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "refuses a file that isn't a list", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      results, expected = fixtures(dir, "not: a list\n")
      expect_raises(Compare::InvalidExpected, /is not a YAML list/) { Compare.compare(results, expected) }
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "refuses a results file without a list of named items with a status, and takes an empty list", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      results, expected = fixtures(dir, COMPARE_EXPECTED)
      ["status: failed\n", "items: none\n", "- a list\n", "items: [\n", "items: [a]\n", "items: [{name: a}]\n", "items: [{status: passed}]\n"].each do |content|
        File.write(results, content)
        expect_raises(Compare::InvalidResults, /is not a results file/) { Compare.compare(results, expected) }
      end
      File.write(results, "items: []\n")
      Compare.compare(results, expected).tests_run.should eq(0)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "compares from the command line, as Markdown or JSON, and refuses a missing file", tags: ["points"] do
    dir = File.tempname("compare")
    begin
      results, expected = fixtures(dir, COMPARE_EXPECTED)
      text = ShellCmd.run_testsuite("compare --results-file #{results} --expected #{expected}")
      text[:status].success?.should be_true
      text[:output].should contain("| `liveness` | passed | **failed** | regression |")

      json = Process.run("./cnti-testsuite compare --output json --results-file #{results} --expected #{expected}", shell: true, output: stdout = IO::Memory.new, error: Process::Redirect::Close)
      json.success?.should be_true
      report = JSON.parse(stdout.to_s)
      report["regressions"].as_a.map(&.as_s).should eq(["liveness"])
      report["improvements"].as_a.map(&.as_s).should eq(["hostpath_mounts"])

      ShellCmd.run_testsuite("compare --results-file #{results}")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      ShellCmd.run_testsuite("compare --results-file #{results} --expected #{dir}/missing.yaml")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      File.write(expected, "not: a list\n")
      ShellCmd.run_testsuite("compare --results-file #{results} --expected #{expected}")[:status].exit_code.should eq(USAGE_EXIT_CODE)
      File.write(expected, COMPARE_EXPECTED)
      File.write(results, "status: failed\n")
      ShellCmd.run_testsuite("compare --results-file #{results} --expected #{expected}")[:status].exit_code.should eq(USAGE_EXIT_CODE)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end
end
