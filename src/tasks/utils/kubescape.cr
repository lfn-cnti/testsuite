require "colorize"
require "log"

module Kubescape

  # Scan output lives with the tool, not in the working directory.
  RESULTS_FILE = "#{tools_path}/kubescape/kubescape_results.json"

  #kubescape scan framework nsa --exclude-namespaces kube-system,kube-public
  def self.scan(cli : String? = nil, control_id : String? = nil, namespace : String? = nil)
    StatusLine.push "Running the Kubescape cluster scan..."
    default_options = "--format json --format-version=v1"
    output_file = RESULTS_FILE
    exclude_namespaces = EXCLUDE_NAMESPACES.join(",")

    namespace_option = "--exclude-namespaces #{exclude_namespaces}"
    namespace_option = "--include-namespaces #{namespace}" if namespace

    if control_id != nil
      cli = "control #{control_id} --output #{control_results_file(control_id)} #{default_options} #{namespace_option}"
    elsif cli == nil
      cli = "framework nsa --use-from #{tools_path}/kubescape/nsa.json --output #{output_file} #{default_options} #{namespace_option}"
    end
    cmd = "#{Setup::KUBESCAPE_BINARY} scan #{cli}"
    Log.info { "scan command: #{cmd}" }
    status = Process.run(
      cmd,
      shell: true,
      output: output = IO::Memory.new,
      error: stderr = IO::Memory.new
    )
    Log.info { "output: #{output.to_s}" }
    Log.info { "stderr: #{stderr.to_s}" }
    StatusLine.pop
    {status: status, output: output.to_s, error: stderr.to_s}
  end

  def self.parse(results_file = RESULTS_FILE)
    Log.info { "kubescape parse" }
    results_json = File.open(results_file) do |f| 
      JSON.parse(f)
    end
    if results_json["controlReports"]?
        results_json["controlReports"]
    else
      EMPTY_JSON
    end
  end

  def self.test_by_test_name(results_json, test_name)
    Log.info { "kubescape test_by_test_name" }

    resp= results_json.as_a.find {|test|test["name"]==test_name}
    if resp
      resp
    else
      EMPTY_JSON_ARRAY
    end
  end

  def self.parse_test_report(test_json : JSON::Any)
    # Abstracted this function into a different class below.
    test_report = TestReportParser.new(report_json: test_json)
    test_report.parse()
  end

  def self.filter_cnf_resources(test_report : TestReport, resource_keys : Array(String)) : TestReport
    failed_resources = test_report.failed_resources.select do |resource|
      CNFManager.resources_includes?(resource_keys, resource.kind, resource.name, resource.namespace)
    end
    test_report.failed_resources = failed_resources
    test_report
  end

  def self.control_results_file(control_id)
    "#{tools_path}/kubescape/kubescape_#{control_id}_results.json"
  end

  class TestReportParser
    def initialize(report_json : JSON::Any)
      @report_json = report_json
      @test_resources = [] of TestResource
    end

    def parse
      test_json = @report_json.as_h

      test_json["ruleReports"].as_a.map do |rule_report|
        rule_name = rule_report["name"].as_s
        unless rule_report["ruleResponses"] == nil
          rule_report.as_h["ruleResponses"].as_a.map do |rule_response|
            parse_rule_response(rule_response, rule_name)
          end
        end
      end

      remediation = test_json.dig?("remediation")
      test_report = TestReport.new(
        name: test_json.dig("name").as_s,
        remediation: remediation ? remediation.as_s : remediation,
        failed_resources: @test_resources
      )

      return test_report
    end

    def parse_rule_response(rule_response : JSON::Any, rule_name : String)
      k8s_objects = rule_response.dig("alertObject", "k8sApiObjects")

      return if k8s_objects == nil
  
      alert_message = rule_response.dig?("alertMessage")
      # Where in the object the rule failed: failedPaths/reviewPaths name the
      # field, fixPaths name it with the value to set. Any of the three may be
      # null in a given response, so they are merged.
      paths = [] of String
      fixes = {} of String => String
      ["failedPaths", "reviewPaths"].each do |key|
        rule_response.dig?(key).try(&.as_a?).try &.each { |path| paths << path.as_s }
      end
      rule_response.dig?("fixPaths").try(&.as_a?).try &.each do |fix|
        path = fix.dig?("path").try(&.as_s?) || next
        paths << path
        fixes[path] = fix.dig?("value").try(&.as_s?) || ""
      end
      k8s_objects.as_a.map do |k8s_obj|
        test_resource = parse_rule_response_k8s_object(k8s_obj, rule_name: rule_name, response_alert: alert_message)
        test_resource.paths = paths.uniq
        test_resource.fixes = fixes
        @test_resources.push(test_resource)
      end
    end

    def parse_rule_response_k8s_object(k8s_obj : JSON::Any, rule_name : String, response_alert : (JSON::Any | Nil)) : TestResource
      kind = k8s_obj["kind"].as_s

      # If object is a cluster-wide resource then name is directly under root key.
      name = parse_k8s_object_name(
        k8s_obj.dig?("name"),
        k8s_obj.dig?("metadata", "name")
      )

      namespace = parse_k8s_object_namespace(k8s_obj.dig?("metadata", "namespace"))

      alert_message = nil
      if response_alert.responds_to?(:as_s?) && response_alert.as_s.size > 0
        alert_message = response_alert.as_s
      else
        alert_message = get_alert_message(name: name, kind: kind, namespace: namespace)
      end

      TestResource.new(
        rule_name: rule_name,
        kind: kind,
        name: name,
        namespace: namespace,
        alert_message: alert_message
      )
    end

    ###
    # Construct custom alert message
    # Used if rule response alert message is an empty string

    def get_alert_message(name : String, kind : String, namespace : Nil)
      "Failed resource: #{kind} #{name}"
    end

    def get_alert_message(name : String, kind : String, namespace : String)
      "Failed resource: #{kind} #{name} in #{namespace} namespace"
    end

    def parse_k8s_object_name(name : Nil, metadata_name : JSON::Any) : String
      metadata_name.as_s
    end

    def parse_k8s_object_name(name : JSON::Any, metadata_name : Nil) : String
      name.as_s
    end

    # Use empty string if name and metadata_name are not valid values
    def parse_k8s_object_name(name, metadata_name) : String
      ""
    end

    def parse_k8s_object_namespace(namespace : JSON::Any)
      namespace.as_s
    end

    def parse_k8s_object_namespace(namespace : Nil)
      nil
    end
  end

  struct TestReport
    property name
    property remediation
    property failed_resources

    def initialize(@name : String, @remediation : String | Nil, @failed_resources : Array(TestResource))
    end
  end

  struct TestResource
    property rule_name
    property kind
    property name
    property namespace
    property alert_message
    # Fields the rule failed on (kubescape failedPaths/reviewPaths/fixPaths),
    # and the value fixPaths suggests for each, when it does.
    property paths : Array(String) = [] of String
    property fixes : Hash(String, String) = {} of String => String

    def initialize(@rule_name : String, @kind : String, @name : String, @namespace : String | Nil, @alert_message : String | Nil)
    end

    # One line per failed field: "<path>" plus the suggested value when
    # kubescape gives a real one ("YOUR_VALUE" is its placeholder for "set it").
    def reason_for(path : String) : String
      value = fixes[path]?
      if value && !value.empty? && value != "YOUR_VALUE"
        "#{path} should be #{value}"
      elsif fixes.has_key?(path)
        "#{path} is not set"
      else
        path
      end
    end

    # The container a path like spec.template.spec.containers[1].x refers to,
    # by name, looked up in the live object; nil when the path is not
    # container-scoped or the object cannot be read.
    def container_for(path : String) : String?
      match = path.match(/^spec\.(?:template\.spec\.)?(containers|initContainers|ephemeralContainers)\[(\d+)\]/)
      return nil unless match
      spec = KubectlClient::Get.resource(kind, name, namespace)
      pod_spec = spec.dig?("spec", "template", "spec") || spec.dig?("spec")
      pod_spec.try(&.dig?(match[1])).try(&.as_a?).try(&.[match[2].to_i]?).try(&.dig?("name")).try(&.as_s?)
    rescue
      nil
    end
  end

  # Records every failed resource of a report into `result`: one entry per
  # failed field when kubescape names the fields (with the container, when
  # the field is a container's), otherwise one entry with the alert message.
  def self.report_failed_resources(test_report : TestReport, result)
    test_report.failed_resources.each do |r|
      if r.paths.empty?
        result.add_impacted_resource(r.kind, r.name, r.namespace, reason: r.alert_message)
      else
        r.paths.each do |path|
          result.add_impacted_resource(r.kind, r.name, r.namespace, container: r.container_for(path), reason: r.reason_for(path))
        end
      end
    end
  end

end
