require "json"
require "yaml"

# A run's results against the results the adopter knows and accepts (#2871):
# a YAML list of {test, status, reason}, where a test the list doesn't name is
# expected to pass. Every test whose result differs is a change: a regression
# when it failed or errored though expected to pass, be skipped or n/a; an
# improvement when it passed though listed as not passing; changed otherwise.
# It reads files only, and never decides what a difference means for the
# job: that is the caller's (a CI wrapper's on_regression, say).
module Compare
  STATUSES    = ["passed", "failed", "skipped", "na", "error"]
  NOT_PASSING = ["failed", "error"]

  class InvalidExpected < Exception
  end

  class InvalidResults < Exception
  end

  record Entry, test : String, status : String, reason : String

  record Change, test : String, expected : String, actual : String, kind : String, reason : String do
    include JSON::Serializable
  end

  class Report
    include JSON::Serializable

    getter results_file : String
    getter expected_file : String
    getter tests_run : Int32
    getter changes : Array(Change)
    getter regressions : Array(String)
    getter improvements : Array(String)
    getter changed : Array(String)
    # Tests the list names without a status a results file has: known, but
    # not how, so not compared.
    getter uncompared : Array(String)
    getter warnings : Array(String)

    def initialize(@results_file, @expected_file, @tests_run, @changes, @uncompared, @warnings)
      @regressions = @changes.select { |c| c.kind == "regression" }.map(&.test)
      @improvements = @changes.select { |c| c.kind == "improvement" }.map(&.test)
      @changed = @changes.map(&.test)
    end
  end

  # The entries of an expectations file, the tests it names without a valid
  # status, and what was wrong with it. Raises InvalidExpected when the file
  # is not a YAML list.
  def self.load_expected(path : String) : Tuple(Array(Entry), Array(String), Array(String))
    list = begin
      YAML.parse(File.read(path)).as_a?
    rescue YAML::ParseException
      nil
    end
    raise InvalidExpected.new("#{path} is not a YAML list of {test, status, reason}") unless list

    entries = [] of Entry
    uncompared = [] of String
    warnings = [] of String
    list.each do |item|
      test = item.as_h? ? item["test"]?.try(&.raw).try(&.to_s).try(&.strip) : nil
      if test.nil? || test.empty?
        warnings << "#{path} has an entry without a test: it is ignored"
        next
      end
      # The first entry for a test counts, whatever a later one says.
      if entries.any? { |e| e.test == test } || uncompared.includes?(test)
        warnings << "#{path} lists #{test} more than once: the first entry counts"
        next
      end
      status = item["status"]?.try(&.raw).try(&.to_s).try(&.strip) || ""
      unless STATUSES.includes?(status)
        # A missing status, a misspelled key or a typo says the test is known
        # but not how: compared, it would turn a known failure into a
        # regression.
        warnings << "#{path} lists #{test} without a status of a results file (#{STATUSES.join(", ")}; it has '#{status}'): #{test} is not compared"
        uncompared << test
        next
      end
      reason = item["reason"]?.try(&.raw).try(&.to_s) || ""
      entries << Entry.new(test, status, reason.gsub(/\s+/, " ").strip)
    end
    {entries, uncompared, warnings}
  end

  # The items of a results file. Raises InvalidResults when it has no list of
  # them, or one without a name and a status: left out of the comparison, they
  # would let it report that nothing differs.
  def self.load_items(path : String) : Array(YAML::Any)
    document = begin
      YAML.parse(File.read(path))
    rescue YAML::ParseException
      nil
    end
    items = document.try { |d| d.as_h? ? d["items"]?.try(&.as_a?) : nil }
    raise InvalidResults.new("#{path} is not a results file: it has no list of items") unless items
    items.each do |item|
      next if item.as_h? && item["name"]?.try(&.as_s?) && item["status"]?.try(&.as_s?)
      raise InvalidResults.new("#{path} is not a results file: one of its items has no name or status")
    end
    items
  end

  def self.compare(results_path : String, expected_path : String) : Report
    entries, uncompared, warnings = load_expected(expected_path)
    items = load_items(results_path)
    changes = [] of Change
    items.each do |item|
      test = item["name"].as_s
      actual = item["status"].as_s
      next if uncompared.includes?(test)
      entry = entries.find { |e| e.test == test }
      expected = entry.try(&.status) || "passed"
      next if actual == expected
      kind = if NOT_PASSING.includes?(actual) && !NOT_PASSING.includes?(expected)
               "regression"
             elsif actual == "passed"
               "improvement"
             else
               "changed"
             end
      changes << Change.new(test, expected, actual, kind, entry.try(&.reason) || "")
    end
    Report.new(results_path, expected_path, items.size, changes, uncompared & items.map(&.["name"].as_s), warnings)
  end

  # The report as Markdown, for a job summary or a terminal: one row per
  # change. The file's reasons are the adopter's text, so they are written
  # as plain text: no HTML, links, images or table cells of their own.
  def self.markdown(report : Report) : String
    String.build do |io|
      io << "### Compared with the expected results (`" << cell(report.expected_file) << "`)\n\n"
      # A test the list names without a valid status is neither a match nor a
      # difference: it isn't counted.
      compared = report.tests_run - report.uncompared.size
      if report.changes.empty?
        io << "Every one of the " << compared << " compared tests has the result the file expects.\n"
      else
        io << report.changes.size << " of the " << compared << " compared tests differ from the file: "
        io << report.regressions.size << " regression(s), " << report.improvements.size << " improvement(s). "
        io << "A test the file doesn't list is expected to pass.\n\n"
        io << "| Test | Expected | Now | |\n|---|---|---|---|\n"
        report.changes.each do |c|
          note = c.kind == "improvement" ? "improvement: remove its entry" : c.kind
          note += "; listed because: #{cell(c.reason)}" unless c.reason.empty?
          io << "| `" << cell(c.test) << "` | " << c.expected << " | **" << c.actual << "** | " << note << " |\n"
        end
      end
      report.uncompared.each { |t| io << "\n_Not compared: `" << cell(t) << "` has no status of a results file in the list._\n" }
    end
  end

  # Text for one Markdown table cell, and for nothing else.
  def self.cell(text : String) : String
    # A backslash first: left alone, one before a [ would cancel its escape.
    text.gsub(/\s+/, " ").gsub("\\", "\\\\")
      .gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      .gsub("[", "\\[").gsub("]", "\\]").gsub("|", "\\|").gsub("`", "'")
      # A bare URL would become a link: its escaped punctuation renders the same.
      .gsub("://", "\\://").gsub(/\bwww\./i) { |www| "#{www[0, 3]}\\." }[0, 600]
  end
end
