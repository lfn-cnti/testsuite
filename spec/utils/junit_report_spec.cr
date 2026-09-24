require "../spec_helper"
require "../../src/tasks/**"

describe "JUnitReport" do
  fixture = "spec/fixtures/results-sample.yml"

  it "maps every results status to the JUnit element CI systems render", tags: ["points"] do
    doc = XML.parse(JUnitReport.from_results(YAML.parse(File.read(fixture))))
    root = doc.first_element_child.not_nil!
    root.name.should eq("testsuites")
    root["tests"].should eq("6")
    root["failures"].should eq("1")
    root["errors"].should eq("1")
    root["skipped"].should eq("2")

    cases = doc.xpath_nodes("//testcase")
    cases.size.should eq(6)

    failed = doc.xpath_nodes("//testcase[@name='privileged_containers']").first
    failed["classname"].should eq("security")
    failed["time"].should eq("3.000")
    failure = failed.xpath_nodes("failure").first
    failure["message"].should eq("Found 2 privileged containers")
    failure["type"].should eq("essential")
    failure.content.should contain("Deployment/coredns-coredns in cnti-default runs privileged")
    failure.content.should contain("impacted: Deployment/coredns-coredns (cnti-default) container coredns: privileged container")
    failure.content.should contain("remediation: Set securityContext.privileged=false on the offending containers")

    doc.xpath_nodes("//testcase[@name='liveness']").first["classname"].should eq("resilience")
    doc.xpath_nodes("//testcase[@name='liveness']/*").should be_empty
    doc.xpath_nodes("//testcase[@name='reasonable_startup_time']/error").first["message"].should eq("Unexpected error occurred")
    doc.xpath_nodes("//testcase[@name='helm_chart_published']/skipped").first["message"].should eq("Chart is not published")
    doc.xpath_nodes("//testcase[@name='operator_installed']/skipped").first["message"].should start_with("not applicable: ")

    # A name the registry does not know lands in its own suite; a list message is joined.
    doc.xpath_nodes("//testsuite[@name='uncategorized']/testcase").size.should eq(1)
    doc.xpath_nodes("//testcase[@name='not_a_test']").first["classname"].should eq("uncategorized")
  end

  it "carries the run's verdict and summary as properties of the root", tags: ["points"] do
    doc = XML.parse(JUnitReport.from_results(YAML.parse(File.read(fixture))))
    prop = ->(name : String) { doc.xpath_nodes("/testsuites/properties/property[@name='#{name}']").first["value"] }
    prop.call("status").should eq("failed")
    prop.call("exit_code").should eq("1")
    prop.call("testsuite_version").should eq("v2.0.0")
    prop.call("summary.essential_passed").should eq("1")
    prop.call("summary.essential_max_passed").should eq("2")
    prop.call("summary.criteria").should contain(%("cert"))
  end

  it "'results_junit' writes the report next to the newest results file", tags: ["points"] do
    ShellCmd.run_testsuite("_divide_by_zero")
    result = ShellCmd.run_testsuite("results_junit")
    result[:status].success?.should be_true
    (/JUnit report: (\S+\.xml)/ =~ result[:output]).should_not be_nil
    report = $1
    File.exists?(report).should be_true
    latest = CNFManager::Points::Results.latest
    newest = File.expand_path(File.readlink(latest), File.dirname(latest))
    report.should eq(newest.sub(/\.yml$/, ".xml"))
    XML.parse(File.read(report)).xpath_nodes("//testcase").should_not be_empty
  end

  it "'results_junit' rejects a missing results file as a usage error", tags: ["points"] do
    result = ShellCmd.run_testsuite("results_junit --results-file /nonexistent/results.yml")
    result[:status].exit_code.should eq(64)
    result[:output].should contain("No results file at '/nonexistent/results.yml'")
  end
end
