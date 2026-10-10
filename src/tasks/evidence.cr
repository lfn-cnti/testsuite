require "sam"
require "./utils/evidence"

desc "Writes the evidence bundle of the newest results file (or --results-file PATH) into --output-dir (default cnti/evidence): the badge as SVG and shields.io JSON, an in-toto Test Result statement, the results file and its JUnit report"
task "evidence" do |_, args|
  results_path = args.named["results-file"]?.try(&.as(String)) || CNFManager::Points::Results.latest
  unless File.exists?(results_path)
    usage_error! "No results file at '#{results_path}': run a test first, or pass --results-file PATH."
  end
  # latest.yml is a link to the newest timestamped file; the bundle carries
  # that file under its own name. Resolved by hand: File.realpath is newer
  # than the oldest Crystal the portability builds compile with.
  real_path = File.symlink?(results_path) ? File.expand_path(File.readlink(results_path), File.dirname(results_path)) : results_path
  output_dir = args.named["output-dir"]?.try(&.as(String)) || Evidence::DEFAULT_DIR

  begin
    files = Evidence.write(real_path, output_dir)
  rescue ex : ArgumentError
    usage_error! ex.message.to_s
  end
  stdout_success "Evidence: #{output_dir} (#{files.join(", ")}; from #{real_path})"
end
