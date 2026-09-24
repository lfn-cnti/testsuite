require "sam"
require "./utils/junit_report"

desc "Writes the newest results file (or --results-file PATH) as a JUnit XML report next to it (or at --junit-file PATH)"
task "results_junit" do |_, args|
  results_path = args.named["results-file"]?.try(&.as(String)) || CNFManager::Points::Results.latest
  unless File.exists?(results_path)
    usage_error! "No results file at '#{results_path}': run a test first, or pass --results-file PATH."
  end
  # latest.yml is a link to the newest timestamped file; name the report after
  # that file. Resolved by hand: File.realpath is newer than the oldest Crystal
  # the portability builds compile with.
  real_path = File.symlink?(results_path) ? File.expand_path(File.readlink(results_path), File.dirname(results_path)) : results_path
  output_path = args.named["junit-file"]?.try(&.as(String)) || real_path.sub(/\.ya?ml$/, "") + ".xml"

  JUnitReport.write(real_path, output_path)
  stdout_success "JUnit report: #{output_path} (from #{real_path})"
end
