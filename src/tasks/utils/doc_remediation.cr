require "./embedded_file_manager"
require "../../modules/release_manager"

EmbeddedFileManager.test_documentation

# The Remediation sections of docs/TEST_DOCUMENTATION.md, keyed by test name,
# read from the copy of the document built into the binary. A test that fails
# without appending a remediation of its own is given this one by the task
# runner, so the results file always says what to do about a failure - and
# the documentation stays the single place that says it.
module DocRemediation
  @@by_test : Hash(String, String)? = nil
  @@entries : Hash(String, Entry)? = nil

  # The documentation of the version this binary was built from: the sections
  # it links to are the ones whose text it shows.
  DOC_URL = "https://github.com/lfn-cnti/testsuite/blob/#{ReleaseManager::DOC_REF}/docs/TEST_DOCUMENTATION.md"

  # A rule of the documentation's "Common rules" that several tests share:
  # its heading, its link and its text.
  record CommonRule, heading : String, url : String, text : String

  # A test's section of the documentation: its heading, what it checks
  # (Overview), what to do when it fails (Remediation), and the complete
  # behaviour for whoever needs it, an agent above all (Details, with the
  # common rules it links to).
  record Entry, heading : String, overview : String?, remediation : String?,
    details : String? = nil, common_rules : Array(CommonRule) = [] of CommonRule do
    # The section's link, with GitHub's anchor for the heading.
    def url : String
      "#{DOC_URL}##{DocRemediation.anchor(heading)}"
    end
  end

  # GitHub's anchor for a heading.
  def self.anchor(heading : String) : String
    heading.downcase.gsub(/[^a-z0-9 _-]/, "").gsub(" ", "-")
  end

  # The documentation of `task_name`, or nil when it has no section.
  def self.entry(task_name : String) : Entry?
    (@@entries ||= parse_entries(TEST_DOCUMENTATION_MD))[task_name.rpartition(":")[2]]?
  end

  def self.parse_entries(markdown : String) : Hash(String, Entry)
    mapping = {} of String => Entry
    rules = parse_common_rules(markdown)
    markdown.split(/\n(?=### )/).each do |section|
      heading = section.match(/\A### ([^\n]+)/).try(&.[1].strip)
      next unless heading
      overview = section.match(/#### Overview\n\n(.+?)\n\n#### /m).try(&.[1].strip)
      remedy = section.match(/#### Remediation\n\n(.+?)\n\n#### /m).try(&.[1].strip)
      details = section.match(/#### Details\n\n(.+?)(?:\n----------|\z)/m).try { |m| details_text(m[1]) }
      linked = details.try { |d| d.scan(/\]\(#([a-z0-9_-]+)\)/).compact_map { |link| rules[link[1]]? }.uniq } || [] of CommonRule
      section.scan(/`\.\/cnti-testsuite ([a-z0-9_:]+)`/) do |usage|
        mapping[usage[1].rpartition(":")[2]] = Entry.new(heading, overview, remedy, details, linked)
      end
    end
    mapping
  end

  # The sections under "## Common rules", by their anchor.
  def self.parse_common_rules(markdown : String) : Hash(String, CommonRule)
    rules = {} of String => CommonRule
    part = markdown.partition(/^## Common rules$/m)[2]
    return rules if part.empty?
    part = part.partition(/^## /m)[0]
    part.split(/\n(?=### )/).each do |section|
      heading = section.match(/\A### ([^\n]+)/).try(&.[1].strip)
      next unless heading
      text = section.sub(/\A### [^\n]+\n/, "").partition(/^----------$/m)[0].strip
      rules[anchor(heading)] = CommonRule.new(heading, "#{DOC_URL}##{anchor(heading)}", text)
    end
    rules
  end

  # A Details section without the HTML that collapses it on the rendered page.
  def self.details_text(section : String) : String?
    text = section.lines.reject { |l| l.strip =~ /\A<\/?details>\z|\A<summary>.*<\/summary>\z/ }.join("\n").strip
    text.empty? ? nil : text
  end

  # The documented remediation for `task_name` (a bare task name; namespaced
  # namespaced usage lines are keyed by their last segment),
  # or nil when the documentation has none.
  def self.for(task_name : String) : String?
    by_test[task_name.rpartition(":")[2]]?
  end

  def self.by_test : Hash(String, String)
    @@by_test ||= parse(TEST_DOCUMENTATION_MD)
  end

  # Each "### Test" section carries "#### Remediation" (one paragraph) and
  # "#### Usage" with the `./cnti-testsuite <task>` line(s) that name the test.
  def self.parse(markdown : String) : Hash(String, String)
    mapping = {} of String => String
    markdown.split(/\n(?=### )/).each do |section|
      remedy = section.match(/#### Remediation\n\n(.+?)\n\n#### /m).try(&.[1].strip)
      next unless remedy
      section.scan(/`\.\/cnti-testsuite ([a-z0-9_:]+)`/) do |usage|
        mapping[usage[1].rpartition(":")[2]] = remedy
      end
    end
    mapping
  end
end
