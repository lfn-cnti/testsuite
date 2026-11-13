require "json"

module CRDConformance
  PLATFORM_GROUPS = {"gateway.networking.k8s.io", "monitoring.coreos.com"}

  def self.identity(definition : JSON::Any) : {String, String}
    {definition.dig("spec", "group").as_s, definition.dig("spec", "names", "kind").as_s}
  end

  def self.findings(definition : JSON::Any) : Array(String)
    findings = [] of String
    versions = definition.dig?("spec", "versions").try(&.as_a?) || [] of JSON::Any
    served = versions.select { |version| version["served"]?.try(&.as_bool?) }
    storage = versions.select { |version| version["storage"]?.try(&.as_bool?) }

    findings << "no served version is declared" if served.empty?
    if storage.size != 1
      findings << "expected one storage version, found #{storage.size}"
    end

    served.each do |version|
      name = version["name"].as_s
      schema = version.dig?("schema", "openAPIV3Schema")
      properties = schema.try(&.dig?("properties")).try(&.as_h?)
      if schema.try(&.dig?("type")).try(&.as_s?) != "object" || properties.nil? || properties.empty?
        findings << "version #{name} needs an OpenAPI v3 object schema that declares top-level properties"
      end
      unless version.dig?("subresources", "status").try(&.as_h?)
        findings << "version #{name} has no status subresource"
      end
    end

    strategy = definition.dig?("spec", "conversion", "strategy").try(&.as_s?) || "None"
    if served.size > 1 && strategy == "None"
      schemas = (served + storage).map { |version| version.dig?("schema", "openAPIV3Schema") }
      if schemas.uniq.size > 1
        findings << "served and storage versions use different schemas without a conversion webhook"
      end
    end

    findings
  end
end
