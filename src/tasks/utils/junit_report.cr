require "xml"
require "yaml"

# Converts a results file into a JUnit XML report: one <testsuite> per test
# category, one <testcase> per results item, and the run's verdict and summary
# as properties of the root. Every CI system renders JUnit natively, so this is
# the one mapping integrations share instead of each parsing the YAML (#2574).
module JUnitReport
  ROOT_NAME     = "cnti-testsuite"
  UNCATEGORIZED = "uncategorized"

  # Reads `results_path` (the YAML results file, or the latest.yml link) and
  # writes the report to `output_path`. Returns the path written.
  def self.write(results_path : String, output_path : String) : String
    results = YAML.parse(File.read(results_path))
    File.write(output_path, from_results(results))
    output_path
  end

  def self.from_results(results : YAML::Any) : String
    items = results["items"]?.try(&.as_a?) || [] of YAML::Any
    categories = CNFManager::TestRegistry.category_of
    grouped = {} of String => Array(YAML::Any)
    items.each do |item|
      category = categories[name_of(item)]? || UNCATEGORIZED
      (grouped[category] ||= [] of YAML::Any) << item
    end

    XML.build(indent: "  ") do |xml|
      xml.element("testsuites", counts(ROOT_NAME, items)) do
        properties(xml, results)
        grouped.each do |category, tests|
          xml.element("testsuite", counts(category, tests)) do
            tests.each { |item| testcase(xml, category, item) }
          end
        end
      end
    end
  end

  private def self.counts(name : String, items : Array(YAML::Any)) : Hash(String, String)
    {
      "name"     => name,
      "tests"    => items.size.to_s,
      "failures" => items.count { |i| status_of(i) == "failed" }.to_s,
      "errors"   => items.count { |i| status_of(i) == "error" }.to_s,
      "skipped"  => items.count { |i| {"skipped", "na"}.includes?(status_of(i)) }.to_s,
      "time"     => seconds(items.sum { |i| runtime_of(i) }),
    }
  end

  # The run's own fields and the summary scalars, so a consumer can show
  # "17 of 19 essential, threshold 15" without opening the YAML.
  private def self.properties(xml : XML::Builder, results : YAML::Any)
    xml.element("properties") do
      {"name", "testsuite_version", "schema_version", "status", "command", "exit_code"}.each do |key|
        value = results[key]?
        xml.element("property", {"name" => key, "value" => value.to_s}) if value && !value.raw.nil?
      end
      if (summary = results["summary"]?.try(&.as_h?))
        summary.each do |key, value|
          rendered = value.raw.is_a?(Hash) || value.raw.is_a?(Array) ? value.to_json : value.to_s
          xml.element("property", {"name" => "summary.#{key}", "value" => rendered})
        end
      end
    end
  end

  private def self.testcase(xml : XML::Builder, category : String, item : YAML::Any)
    status = status_of(item)
    message = lines(item["message"]?).join("; ")
    xml.element("testcase", {"classname" => category, "name" => name_of(item), "time" => seconds(runtime_of(item))}) do
      case status
      when "failed"
        xml.element("failure", {"message" => message, "type" => item["type"]?.to_s}) { xml.text(body(item)) }
      when "error"
        xml.element("error", {"message" => message, "type" => item["type"]?.to_s}) { xml.text(body(item)) }
      when "skipped"
        xml.element("skipped", {"message" => message})
      when "na"
        xml.element("skipped", {"message" => "not applicable: #{message}"})
      end
    end
  end

  # Details, impacted resources and remediation, one per line, as the failure body.
  private def self.body(item : YAML::Any) : String
    out = lines(item["details"]?)
    (item["impacted_resources"]?.try(&.as_a?) || [] of YAML::Any).each do |res|
      ref = "#{res["kind"]?}/#{res["name"]?}"
      ref += " (#{res["namespace"]?})" if res["namespace"]?
      ref += " container #{res["container"]?}" if res["container"]?
      ref += " pod #{res["pod"]?}" if res["pod"]?
      reason = res["reason"]?
      out << "impacted: #{ref}#{reason ? ": #{reason}" : ""}"
    end
    lines(item["remediation"]?).each { |line| out << "remediation: #{line}" }
    out.join("\n")
  end

  # message, details and remediation may be a string or a list of strings.
  private def self.lines(value : YAML::Any?) : Array(String)
    return [] of String if value.nil? || value.raw.nil?
    if (list = value.as_a?)
      list.map(&.to_s)
    else
      [value.to_s]
    end
  end

  private def self.name_of(item : YAML::Any) : String
    item["name"]?.to_s
  end

  private def self.status_of(item : YAML::Any) : String
    item["status"]?.try(&.as_s?) || "error"
  end

  private def self.runtime_of(item : YAML::Any) : Float64
    value = item["task_runtime"]?
    value.try(&.as_f?) || value.try(&.as_i?).try(&.to_f) || 0.0
  end

  private def self.seconds(value : Float64) : String
    sprintf("%.3f", value)
  end
end
