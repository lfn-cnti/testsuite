require "colorize"
require "log"

module Kubescape

  #kubescape scan framework nsa --exclude-namespaces kube-system,kube-public
  def self.scan(cli : String? = nil, control_id : String? = nil, namespace : String? = nil)
    default_options = "--format json --format-version=v1"
    output_file = "kubescape_results.json"
    exclude_namespaces = EXCLUDE_NAMESPACES.join(",")

    namespace_option = "--exclude-namespaces #{exclude_namespaces}"
    namespace_option = "--include-namespaces #{namespace}" if namespace

    if control_id != nil
      cli = "control #{control_id} --output #{control_results_file(control_id)} #{default_options} #{namespace_option}"
    elsif cli == nil
      cli = "framework nsa --use-from #{tools_path}/kubescape/nsa.json --output #{output_file} #{default_options} #{namespace_option}"
    end
    cmd = "#{tools_path}/kubescape/kubescape scan #{cli}"
    Log.info { "scan command: #{cmd}" }
    status = Process.run(
      cmd,
      shell: true,
      output: output = IO::Memory.new,
      error: stderr = IO::Memory.new
    )
    Log.info { "output: #{output.to_s}" }
    Log.info { "stderr: #{stderr.to_s}" }
    {status: status, output: output.to_s, error: stderr.to_s}
  end

  def self.parse(results_file="kubescape_results.json")
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
    "kubescape_#{control_id}_results.json"
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
      k8s_objects.as_a.map do |k8s_obj|
        test_resource = parse_rule_response_k8s_object(k8s_obj, rule_name: rule_name, response_alert: alert_message)
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

    def initialize(@rule_name : String, @kind : String, @name : String, @namespace : String | Nil, @alert_message : String | Nil)
    end
  end

end
