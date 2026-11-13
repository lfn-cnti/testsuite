require "json"

module CRDConformance
  BUILTIN_GROUPS = {"autoscaling", "authentication.k8s.io", "authorization.k8s.io", "certificates.k8s.io", "events.k8s.io", "resource.k8s.io", "apiregistration.k8s.io", "internal.apiserver.k8s.io"}

  def self.identity(definition : JSON::Any) : {String, String}?
    group = definition.dig?("spec", "group").try(&.as_s?).try(&.presence)
    kind = definition.dig?("spec", "names", "kind").try(&.as_s?).try(&.presence)
    {group, kind} if group && kind
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
      name = version["name"]?.try(&.as_s?) || "(unnamed)"
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
