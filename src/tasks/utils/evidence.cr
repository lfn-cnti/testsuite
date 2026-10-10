require "json"
require "yaml"
require "digest/sha256"
require "file_utils"
require "./junit_report"

# The evidence bundle a project publishes next to its badge, derived from one
# results file: the badge (SVG, and shields.io endpoint JSON), an in-toto
# Statement with the Test Result predicate, and copies of the results file and
# its JUnit report. The results contract lives here, so the files derived from
# it do too; the GitHub Action and the GitLab CI/CD component call `evidence`
# rather than carrying their own badge scripts (#2740, #2738).
module Evidence
  DEFAULT_DIR    = "cnti/evidence"
  BADGE_SVG      = "cnti-badge.svg"
  BADGE_JSON     = "cnti-badge.json"
  STATEMENT_JSON = "cnti-evidence.json"

  STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
  PREDICATE_TYPE = "https://in-toto.io/attestation/test-result/v0.1"
  # The version of the `cnti` block of the predicate (docs/cnti-evidence.schema.json).
  CNTI_SCHEMA_VERSION = 1

  # The results file's `status` and the `result` of the in-toto predicate.
  RESULT_OF = {"passed" => "PASSED", "failed" => "FAILED", "error" => "FAILED"}

  # CNTi logo (symbol + wordmark, colour) from https://github.com/lfn-cnti/artwork
  # (cnti-logo/stacked/color/CNTi Logo_COLOR.svg), viewBox 0 0 255.99 69.68.
  LOGO_VIEWBOX = "0 0 255.99 69.68"
  LOGO_PATHS   = "<path fill=\"#213666\" d=\"M156.58,31.9l-6.74,5.71c-3.02-3.4-6.8-5.07-11.35-5.07-3.98,0-7.31,1.35-10.07,4.04s-4.11,6.03-4.11,10.07,1.35,7.38,4.04,10.07c2.76,2.63,6.09,3.98,10.14,3.98,4.62,0,8.4-1.73,11.42-5.13l6.74,5.71c-4.55,5.32-11.03,8.4-18.15,8.4-6.73,0-12.38-2.18-17.06-6.54-4.68-4.43-6.99-9.88-6.99-16.48s2.31-12.06,6.99-16.49,10.33-6.61,17.06-6.61c7.12,0,13.53,3.14,18.09,8.34Z\"/><path fill=\"#213666\" d=\"M162.23,68.97V24.26h8.79l21.42,27.77v-27.77h9.56v44.71h-8.08l-22.13-28.54v28.54h-9.56Z\"/><path fill=\"#213666\" d=\"M219.32,68.97v-35.73h-12.12v-8.98h33.93v8.98h-11.93v35.73h-9.88Z\"/><path fill=\"#213666\" d=\"M246.4,68.97v-32.33h9.56v32.33h-9.56Z\"/><rect fill=\"#4fb04e\" x=\"246.36\" y=\"24.28\" width=\"9.63\" height=\"9\"/><path fill=\"#0086c1\" d=\"M80.83,24.71v7.62c6.34,1.9,10.97,7.78,10.97,14.72s-4.59,12.77-10.89,14.69v7.64c10.43-2.08,18.31-11.31,18.31-22.34s-7.92-20.29-18.39-22.34Z\"/><path fill=\"#0086c1\" d=\"M21.82,61.86h-4.51c-.16-.02-.39-.03-.55-.04-.17-.01-.47-.02-.63-.06-.61-.09-1.31-.22-1.89-.41-4.49-1.39-7.63-5.88-6.66-10.58,1.66-7.71,11.75-10.1,17.25-4.79l5.66-4.73c-2.2-3.44-3.43-7.43-3.54-11.49-.23-7.32,3.15-14.33,9.45-18.2,6.76-4.17,16.15-4.44,23.19-.81,3.92,2.03,6.86,5.46,8.37,9.55h8.71c-.13-.59-.29-1.17-.48-1.75-2.03-6.43-6.75-12.1-12.75-15.14C59.53,1.37,55.17.32,50.82.08c-17.64-1.22-32.51,11.96-31.61,29.98.09,1.96.38,3.91.86,5.82-5-.69-10.26.72-14.13,4.02C2.51,42.75.24,47.08.03,51.55c-.56,10.27,8.19,18.05,18.2,17.73h1.74s.67,0,1.86,0v-7.42Z\"/><rect fill=\"#4fb04e\" x=\"68.23\" y=\"24.19\" width=\"8.86\" height=\"45.17\"/><rect fill=\"#4fb04e\" x=\"54.17\" y=\"33.06\" width=\"8.9\" height=\"36.3\"/><rect fill=\"#4fb04e\" x=\"40.15\" y=\"42.17\" width=\"8.89\" height=\"27.2\"/><rect fill=\"#4fb04e\" x=\"26.09\" y=\"51.23\" width=\"8.93\" height=\"18.13\"/>"
  # The monochrome symbol for shields.io's endpoint badge (its logo slot is on a dark panel).
  LOGO_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 99.21 69.39\" fill=\"#fff\"><path d=\"M80.83,24.71v7.62c6.34,1.9,10.97,7.78,10.97,14.72s-4.59,12.77-10.89,14.69v7.64c10.43-2.08,18.31-11.31,18.31-22.34s-7.92-20.29-18.39-22.34Z\"/><path d=\"M21.82,61.86h-4.51c-.16-.02-.39-.03-.55-.04-.17-.01-.47-.02-.63-.06-.61-.09-1.31-.22-1.89-.41-4.49-1.39-7.63-5.88-6.66-10.58,1.66-7.71,11.75-10.1,17.25-4.79l5.66-4.73c-2.2-3.44-3.43-7.43-3.54-11.49-.23-7.32,3.15-14.33,9.45-18.2,6.76-4.17,16.15-4.44,23.19-.81,3.92,2.03,6.86,5.46,8.37,9.55h8.71c-.13-.59-.29-1.17-.48-1.75-2.03-6.43-6.75-12.1-12.75-15.14C59.53,1.37,55.17.32,50.82.08c-17.64-1.22-32.51,11.96-31.61,29.98.09,1.96.38,3.91.86,5.82-5-.69-10.26.72-14.13,4.02C2.51,42.75.24,47.08.03,51.55c-.56,10.27,8.19,18.05,18.2,17.73h1.74s.67,0,1.86,0v-7.42Z\"/><rect x=\"68.23\" y=\"24.19\" width=\"8.86\" height=\"45.17\"/><rect x=\"54.17\" y=\"33.06\" width=\"8.9\" height=\"36.3\"/><rect x=\"40.15\" y=\"42.17\" width=\"8.89\" height=\"27.2\"/><rect x=\"26.09\" y=\"51.23\" width=\"8.93\" height=\"18.13\"/></svg>"

  # The badge names the test set, not the task: the cert task runs the
  # essential tests, so its badge reads "essential". Any other task is named
  # as it is.
  def self.label_set(task : String) : String
    task == "cert" ? "essential" : task
  end

  # The task the results file was produced by: the first word of `command`
  # after the binary that is not an option. "cert" when the file says nothing.
  def self.task_of(results : YAML::Any) : String
    command = results["command"]?.try(&.as_s?) || ""
    words = command.split
    words.shift? # the binary
    words.find { |word| !word.starts_with?("-") } || "cert"
  end

  def self.status_of(results : YAML::Any) : String
    results["status"]?.try(&.as_s?) || "error"
  end

  # "17/19": tests passed over the maximum for the task that ran.
  def self.message_of(results : YAML::Any) : String
    summary = results["summary"]?
    passed = summary.try(&.["passed"]?).try(&.as_i?)
    max_passed = summary.try(&.["max_passed"]?).try(&.as_i?)
    "#{passed.nil? ? "?" : passed}/#{max_passed.nil? ? "?" : max_passed}"
  end

  # Hex colour of the verdict panel and shields.io's name for it.
  def self.color(status : String) : {String, String}
    case status
    when "passed" then {"4c1", "brightgreen"}
    when "failed" then {"e05d44", "red"}
    else               {"9f9f9f", "lightgrey"}
    end
  end

  # Flat shields-style SVG: white panel with the colour logo and the test set in
  # the logo's navy, then the coloured verdict panel. The geometry matches the
  # badge the action and the component published before `evidence` existed
  # (about 6.5px per character of Verdana 11px, plus padding), so a badge does
  # not change shape when a project moves to this command.
  def self.badge_svg(set : String, message : String, status : String) : String
    label = "CNTi #{set}"
    hex, _ = color(status)
    logo_h = 13; logo_w = 48; pad = 5; gap = 5
    label_tw = set.size * 65 // 10
    lw = pad + logo_w + gap + label_tw + pad
    mw = message.size * 65 // 10 + 10
    tw = lw + mw
    label_x = pad + logo_w + gap + label_tw // 2
    <<-SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="#{tw}" height="20" role="img" aria-label="#{label}: #{message}">
      <title>#{label}: #{message}</title>
      <linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient>
      <clipPath id="r"><rect width="#{tw}" height="20" rx="3" fill="#fff"/></clipPath>
      <g clip-path="url(#r)"><rect width="#{lw}" height="20" fill="#fff"/><rect x="#{lw}" width="#{mw}" height="20" fill="##{hex}"/><rect x="#{lw}" width="#{mw}" height="20" fill="url(#s)"/></g>
      <rect x=".5" y=".5" width="#{tw - 1}" height="19" rx="3" fill="none" stroke="#ccc"/>
      <svg x="#{pad}" y="1.5" width="#{logo_w}" height="#{logo_h}" viewBox="#{LOGO_VIEWBOX}">#{LOGO_PATHS}</svg>
      <g text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11">
        <text x="#{label_x}" y="14.5" fill="#213666">#{set}</text>
        <text x="#{lw + mw // 2}" y="15.5" fill="#010101" fill-opacity=".3">#{message}</text><text x="#{lw + mw // 2}" y="14.5" fill="#fff">#{message}</text>
      </g>
    </svg>
    SVG
  end

  # shields.io endpoint format (https://shields.io/badges/endpoint-badge).
  def self.badge_json(set : String, message : String, status : String) : String
    _, name = color(status)
    {schemaVersion: 1, label: "CNTi #{set}", message: message, color: name, logoSvg: LOGO_SVG}.to_json
  end

  # The in-toto Statement: the results file is the subject, the Test Result
  # predicate carries the verdict and the test names, and `cnti` the fields a
  # reader needs without opening the YAML.
  def self.statement(results_path : String, results : YAML::Any) : String
    items = results["items"]?.try(&.as_a?) || [] of YAML::Any
    names_with = ->(wanted : String) {
      items.select { |i| i["status"]?.try(&.as_s?) == wanted }.compact_map { |i| i["name"]?.try(&.as_s?) }
    }
    status = status_of(results)
    task = task_of(results)
    summary = results["summary"]?
    scalar = ->(key : String) { summary.try(&.[key]?).try(&.raw) }
    criteria = summary.try(&.["criteria"]?)

    {
      "_type"         => STATEMENT_TYPE,
      "subject"       => [{"name" => File.basename(results_path), "digest" => {"sha256" => sha256_of(results_path)}}],
      "predicateType" => PREDICATE_TYPE,
      "predicate"     => {
        "result"      => RESULT_OF[status]? || "FAILED",
        "passedTests" => names_with.call("passed"),
        "failedTests" => names_with.call("failed"),
        "warnedTests" => [] of String,
        "cnti"        => {
          "schema_version"       => CNTI_SCHEMA_VERSION,
          "testsuite_version"    => results["testsuite_version"]?.try(&.as_s?) || "",
          "task"                 => task,
          "label"                => "CNTi #{label_set(task)}",
          "status"               => status,
          "exit_code"            => results["exit_code"]?.try(&.as_i?),
          "passed"               => scalar.call("passed"),
          "max_passed"           => scalar.call("max_passed"),
          "essential_passed"     => scalar.call("essential_passed"),
          "essential_max_passed" => scalar.call("essential_max_passed"),
          "points"               => scalar.call("points"),
          "maximum_points"       => scalar.call("maximum_points"),
          "criteria"             => criteria ? JSON.parse(criteria.to_json) : nil,
          "run_date"             => run_date_of(results_path),
          "results_file"         => File.basename(results_path),
          "self_published"       => true,
        },
      },
    }.to_pretty_json
  end

  # Writes the bundle for `results_path` (a timestamped results file, not the
  # latest.yml link) into `output_dir`. Returns the files written, by name.
  # A file without a verdict is refused: a run still `running` never finished.
  def self.write(results_path : String, output_dir : String) : Array(String)
    results = YAML.parse(File.read(results_path))
    status = status_of(results)
    if status == "running" || results["exit_code"]?.try(&.raw).nil?
      raise ArgumentError.new("#{results_path} has no verdict (status: #{status}): the run did not finish")
    end

    FileUtils.mkdir_p(output_dir)
    set = label_set(task_of(results))
    message = message_of(results)
    written = [] of String
    write_file = ->(name : String, content : String) {
      File.write(File.join(output_dir, name), content)
      written << name
    }
    write_file.call(BADGE_SVG, badge_svg(set, message, status))
    write_file.call(BADGE_JSON, badge_json(set, message, status) + "\n")
    write_file.call(STATEMENT_JSON, statement(results_path, results) + "\n")

    results_name = File.basename(results_path)
    FileUtils.cp(results_path, File.join(output_dir, results_name))
    written << results_name
    junit_name = results_name.sub(/\.ya?ml$/, "") + ".xml"
    JUnitReport.write(results_path, File.join(output_dir, junit_name))
    written << junit_name
    written
  end

  private def self.sha256_of(path : String) : String
    Digest::SHA256.hexdigest(File.read(path))
  end

  # The run's date from the results file's timestamp name, else the file's mtime.
  private def self.run_date_of(path : String) : String
    if (m = File.basename(path).match(/(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})/))
      "#{m[1]}-#{m[2]}-#{m[3]}T#{m[4]}:#{m[5]}:#{m[6]}Z"
    else
      File.info(path).modification_time.to_utc.to_s("%Y-%m-%dT%H:%M:%SZ")
    end
  end
end
