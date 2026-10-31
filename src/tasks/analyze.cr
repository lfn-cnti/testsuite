require "sam"
require "./utils/analyze"

desc "Prepares the opt-in AI analysis of the tests that failed or errored in the newest run (or --results-file PATH), and renders the model's answer: `analyze prepare --provider anthropic|openai-compatible --model M --dir DIR` writes the request, which the caller sends with its own key, and `analyze render --dir DIR --response FILE --http-status N` checks the answer and writes DIR/analysis.md"
task "analyze" do |_, args|
  # Flags are in args.raw too; the first other word is the step.
  step = args.raw.reject("analyze_expected").first?.try(&.to_s)
  dir = args.named["dir"]?.try(&.as(String))
  usage_error! "analyze needs --dir DIR, where the request and the analysis go." unless dir
  case step
  when "prepare"
    results_path = args.named["results-file"]?.try(&.as(String)) || CNFManager::Points::Results.latest
    unless File.exists?(results_path)
      usage_error! "No results file at '#{results_path}': run a test first, or pass --results-file PATH."
    end
    provider = args.named["provider"]?.try(&.as(String)) || "anthropic"
    model = args.named["model"]?.try(&.as(String))
    usage_error! "analyze prepare needs --model, the model's id." unless model && !model.empty?
    level = args.named["include"]?.try(&.as(String)) || "facts"
    usage_error! "--include is '#{level}': facts or logs." unless {"facts", "logs"}.includes?(level)
    max_kb = (args.named["max-facts-kb"]?.try(&.as(String)) || Analyze::DEFAULT_MAX_FACTS_KB.to_s).to_i?
    usage_error! "--max-facts-kb must be a whole number of KB from 1 to 1024." unless max_kb && 1 <= max_kb <= 1024
    expected = args.named["expected"]?.try(&.as(String))
    usage_error! "--expected '#{expected}' is not a file." if expected && !File.file?(expected)
    opts = Analyze::Options.new(provider, model, args.named["endpoint"]?.try(&.as(String)), level == "logs",
      max_kb * 1024, expected, args.raw.includes?("analyze_expected"))
    begin
      sent = Analyze.prepare(results_path, opts, dir)
    rescue ex : Analyze::Error | Compare::InvalidExpected
      usage_error! ex.message.to_s
    end
    JSON.parse(File.read(File.join(dir, "state.json")))["notes"].as_a.each { |n| puts "note: #{n.as_s}" }
    if sent
      puts "Request: #{File.join(dir, "request.json")} (send it to the URL in #{File.join(dir, "request.env")}, with the headers in request.headers and the key in KEY_HEADER)"
    else
      puts "No test failed or errored that isn't expected: nothing to send#{File.exists?(File.join(dir, "analysis.md")) ? "; #{File.join(dir, "analysis.md")} lists the expected ones" : ""}"
    end
  when "render"
    response = args.named["response"]?.try(&.as(String))
    usage_error! "analyze render needs --response FILE, the model's answer." unless response
    status = args.named["http-status"]?.try(&.as(String)).try(&.to_i?)
    usage_error! "analyze render needs --http-status N, the HTTP status of the answer." unless status
    usage_error! "#{dir} has no state.json: run analyze prepare first." unless File.exists?(File.join(dir, "state.json"))
    # One line each, so a caller can turn them into its platform's annotations.
    Analyze.render(dir, response, status).each { |w| puts w.starts_with?("note: ") ? w : "warning: #{w}" }
    puts "Analysis: #{File.join(dir, "analysis.md")}" if File.exists?(File.join(dir, "analysis.md"))
  else
    usage_error! "analyze needs a step: prepare or render."
  end
end
