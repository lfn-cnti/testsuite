require "./embedded_file_manager"

EmbeddedFileManager.test_documentation

# The Remediation sections of docs/TEST_DOCUMENTATION.md, keyed by test name,
# read from the copy of the document built into the binary. A test that fails
# without appending a remediation of its own is given this one by the task
# runner, so the results file always says what to do about a failure - and
# the documentation stays the single place that says it.
module DocRemediation
  @@by_test : Hash(String, String)? = nil
  @@entries : Hash(String, Entry)? = nil

  DOC_URL = "https://github.com/lfn-cnti/testsuite/blob/main/docs/TEST_DOCUMENTATION.md"

  # A test's section of the documentation: its heading, what it checks
  # (Overview) and what to do when it fails (Remediation).
  record Entry, heading : String, overview : String?, remediation : String? do
    # The section's link, with GitHub's anchor for the heading.
    def url : String
      anchor = heading.downcase.gsub(/[^a-z0-9 _-]/, "").gsub(" ", "-")
      "#{DOC_URL}##{anchor}"
    end
  end

  # The documentation of `task_name`, or nil when it has no section.
  def self.entry(task_name : String) : Entry?
    (@@entries ||= parse_entries(TEST_DOCUMENTATION_MD))[task_name.rpartition(":")[2]]?
  end

  def self.parse_entries(markdown : String) : Hash(String, Entry)
    mapping = {} of String => Entry
    markdown.split(/\n(?=### )/).each do |section|
      heading = section.match(/\A### ([^\n]+)/).try(&.[1].strip)
      next unless heading
      overview = section.match(/#### Overview\n\n(.+?)\n\n#### /m).try(&.[1].strip)
      remedy = section.match(/#### Remediation\n\n(.+?)\n\n#### /m).try(&.[1].strip)
      section.scan(/`\.\/cnti-testsuite ([a-z0-9_:]+)`/) do |usage|
        mapping[usage[1].rpartition(":")[2]] = Entry.new(heading, overview, remedy)
      end
    end
    mapping
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
