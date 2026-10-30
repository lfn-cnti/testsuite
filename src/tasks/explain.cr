require "sam"
require "./utils/explain"

desc "Explains the tests of the newest run (or --results-file PATH) that did not pass: the result, what the test checks, and its own lines of the run's debug log; `explain <test>` for one test"
task "explain" do |_, args|
  results_path = args.named["results-file"]?.try(&.as(String)) || CNFManager::Points::Results.latest
  unless File.exists?(results_path)
    usage_error! "No results file at '#{results_path}': run a test first, or pass --results-file PATH."
  end
  test = args.raw.first?.try(&.to_s)
  begin
    report = Explain.report_json(results_path, test)
  rescue ex : Explain::UnknownTest
    usage_error! ex.message.to_s
  end
  # --output json: the explanation is the sole thing on stdout.
  puts json_output? ? report : Explain.text(report)
end
