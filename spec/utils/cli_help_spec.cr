require "./../spec_helper"
require "../../src/tasks/utils/cli_args_validation"

# Parses `help tasks` output into {task path => description}. A row is
# "  <path>" padded to the description column; a path too long for that column
# pushes its description onto the following indented line(s).
private def parse_task_rows(output : String) : Hash(String, String)
  rows = {} of String => String
  last_path = ""
  output.each_line do |line|
    next if line.strip.empty?
    if line.starts_with?("  ") && !line.starts_with?("   ")
      # "  name<padding>description" or "  name" alone
      rest = line[2..].rstrip
      path, _, description = rest.partition(" ")
      rows[path] = description.strip
      last_path = path
    elsif line.starts_with?("   ") && !last_path.empty?
      rows[last_path] = "#{rows[last_path]} #{line.strip}".strip
    end
  end
  rows
end

describe "CLI help" do
  it "prints usage without a terminal and exits 0", tags: ["points"] do
    # SAM's help shelled out to `tput cols` and crashed with "Invalid Int32" when
    # TERM was unset, which is the normal case in containers and CI.
    result = ShellCmd.run_testsuite("help", "env -u TERM")
    result[:status].exit_code.should eq(0)
    result[:output].should contain("USAGE")
    result[:output].should_not contain("Invalid Int32")
  end

  it "'-h' prints the same single help page and exits 0", tags: ["points"] do
    help = ShellCmd.run_testsuite("help")
    flag = ShellCmd.run_testsuite("-h")
    flag[:status].exit_code.should eq(0)
    flag[:output].should eq(help[:output])
    # -h used to print the option banner and then fall through to the task table.
    flag[:output].scan(/^USAGE$/m).size.should eq(1)
  end

  it "'--version' prints the version and exits 0", tags: ["points"] do
    result = ShellCmd.run_testsuite("--version")
    result[:status].exit_code.should eq(0)
    result[:output].should contain("CNF TestSuite version:")
  end

  it "'help tasks' groups tasks and describes every one it lists", tags: ["points"] do
    result = ShellCmd.run_testsuite("help tasks")
    result[:status].exit_code.should eq(0)

    result[:output].should contain("GETTING STARTED")
    result[:output].should contain("TEST SUITES")

    rows = parse_task_rows(result[:output])
    rows.should_not be_empty
    rows.each { |path, description| description.should_not eq("") }

    # Internal tasks are hidden by the leading-underscore convention.
    rows.keys.any?(&.starts_with?("_")).should be_false
    rows.keys.any?(&.includes?(":_")).should be_false
    rows.keys.should_not contain("generate:makefile")

    # Real tasks are still listed.
    rows.keys.should contain("liveness")
    rows.keys.should contain("cnf_install")
  end

  it "'help <task>' describes a single task", tags: ["points"] do
    result = ShellCmd.run_testsuite("help liveness")
    result[:status].exit_code.should eq(0)
    result[:output].should contain("cnf-testsuite liveness")
    result[:output].should contain("liveness probe")
  end

  it "suggests the closest task for an unknown name", tags: ["points"] do
    result = ShellCmd.run_testsuite("help livenes")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("Did you mean 'liveness'?")

    # ... and on the invocation path, not just via `help`.
    result = ShellCmd.run_testsuite("livenes")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("Did you mean 'liveness'?")

    # Nothing close enough gets no misleading suggestion.
    result = ShellCmd.run_testsuite("zzzzzzzz")
    result[:output].should_not contain("Did you mean")
  end
end
