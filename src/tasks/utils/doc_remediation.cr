require "./embedded_file_manager"

EmbeddedFileManager.test_documentation

# The Remediation sections of docs/TEST_DOCUMENTATION.md, keyed by test name,
# read from the copy of the document built into the binary. A test that fails
# without appending a remediation of its own is given this one by the task
# runner, so the results file always says what to do about a failure - and
# the documentation stays the single place that says it.
module DocRemediation
  @@by_test : Hash(String, String)? = nil

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
  # "#### Usage" with the `./cnf-testsuite <task>` line(s) that name the test.
  def self.parse(markdown : String) : Hash(String, String)
    mapping = {} of String => String
    markdown.split(/\n(?=### )/).each do |section|
      remedy = section.match(/#### Remediation\n\n(.+?)\n\n#### /m).try(&.[1].strip)
      next unless remedy
      section.scan(/`\.\/cnf-testsuite ([a-z0-9_:]+)`/) do |usage|
        mapping[usage[1].rpartition(":")[2]] = remedy
      end
    end
    mapping
  end
end
