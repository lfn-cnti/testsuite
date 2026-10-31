require "sam"
require "./utils/compare"

desc "Compares the newest results file (or --results-file PATH) with --expected FILE, a YAML list of the results you know and accept ({test, status, reason}; a test it doesn't list is expected to pass), and lists every test whose result differs: regressions, improvements and other changes"
task "compare" do |_, args|
  results_path = args.named["results-file"]?.try(&.as(String)) || CNFManager::Points::Results.latest
  unless File.exists?(results_path)
    usage_error! "No results file at '#{results_path}': run a test first, or pass --results-file PATH."
  end
  expected_path = args.named["expected"]?.try(&.as(String))
  unless expected_path && File.file?(expected_path)
    usage_error! "compare needs --expected FILE, the YAML list of the results you expect#{expected_path ? ": '#{expected_path}' is not a file" : ""}."
  end
  # latest.yml is a link to the newest timestamped file; the report names that
  # file. Resolved by hand, as in results_junit.
  real_path = File.symlink?(results_path) ? File.expand_path(File.readlink(results_path), File.dirname(results_path)) : results_path
  begin
    report = Compare.compare(real_path, expected_path)
  rescue ex : Compare::InvalidExpected | Compare::InvalidResults
    usage_error! ex.message.to_s
  end
  report.warnings.each { |w| Log.for("compare").warn { w } }
  # A difference is not a failure here: what it means for a job is the
  # caller's decision. --output json: the report is the sole thing on stdout.
  puts json_output? ? report.to_json : Compare.markdown(report)
end
