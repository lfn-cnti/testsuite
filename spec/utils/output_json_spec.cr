require "../spec_helper"
require "json"

# End-to-end proof of the --output json contract: run the binary, capture
# stdout and stderr separately (run_testsuite merges them with 2>&1, so this
# uses Process.run directly), and assert stdout is exactly the results document
# as JSON while the human "Results:" line is on stderr. `_divide_by_zero` writes
# a results file without needing a cluster.
describe "--output json" do
  it "prints only the results document as JSON on stdout, with logs on stderr", tags: ["points"] do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    Process.run("./cnti-testsuite _divide_by_zero --output json", shell: true, output: stdout, error: stderr)

    # stdout is a single JSON document matching the results-file shape.
    doc = JSON.parse(stdout.to_s)
    doc["name"].as_s.should eq("cnti testsuite")
    doc["items"].as_a.should_not be_empty

    # The human "Results:" line is redirected to stderr, never on stdout.
    stderr.to_s.should contain("Results:")
    stdout.to_s.should_not contain("Results:")
  end
end
