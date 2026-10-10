require "json"
require "yaml"

# Minimal JSON-Schema validator covering only the constructs the suite's
# schemas use ($ref, type, enum, const, required, additionalProperties:false,
# array items). Driven by the schema file itself so it acts as a drift guard:
# any divergence between an emitted file and the published schema (added,
# removed or renamed field, wrong type) fails the spec. Shared by the results
# file spec and the evidence statement spec.
def resolve_schema_ref(schema : JSON::Any, defs : JSON::Any) : JSON::Any
  if ref = schema["$ref"]?
    defs[ref.as_s.split("/").last]
  else
    schema
  end
end

def yaml_matches_type?(instance : YAML::Any, type_name : String) : Bool
  case type_name
  when "object"  then !instance.as_h?.nil?
  when "array"   then !instance.as_a?.nil?
  when "string"  then !instance.as_s?.nil?
  when "integer" then !instance.as_i?.nil? || !instance.as_i64?.nil?
  when "number"  then !instance.as_i?.nil? || !instance.as_i64?.nil? || !instance.as_f?.nil?
  when "boolean" then !instance.as_bool?.nil?
  when "null"    then instance.raw.nil?
  else                false
  end
end

def validate_against_schema(instance : YAML::Any, schema : JSON::Any, defs : JSON::Any, path : String = "$")
  schema = resolve_schema_ref(schema, defs)

  if const = schema["const"]?
    raise "#{path}: expected #{const.raw.inspect}, got #{instance.raw.inspect}" unless instance.raw == const.raw
    return
  end
  if enum_node = schema["enum"]?
    allowed = enum_node.as_a.map(&.raw)
    raise "#{path}: #{instance.raw.inspect} not in enum #{allowed}" unless allowed.includes?(instance.raw)
    return
  end

  if type = schema["type"]?
    names = type.as_s? ? [type.as_s] : type.as_a.map(&.as_s)
    raise "#{path}: expected type #{names}, got #{instance.raw.inspect}" unless names.any? { |n| yaml_matches_type?(instance, n) }
  end

  if props = schema["properties"]?
    if schema["additionalProperties"]?.try(&.as_bool?) == false
      instance.as_h.each_key do |k|
        raise "#{path}: unexpected key '#{k.as_s}' not declared in schema" unless props.as_h.has_key?(k.as_s)
      end
    end
    if required = schema["required"]?
      required.as_a.each do |rk|
        raise "#{path}: missing required key '#{rk.as_s}'" if instance[rk.as_s]?.nil?
      end
    end
    props.as_h.each do |key, subschema|
      if value = instance[key]?
        validate_against_schema(value, subschema, defs, "#{path}.#{key}")
      end
    end
  end

  if items = schema["items"]?
    instance.as_a.each_with_index do |element, i|
      validate_against_schema(element, items, defs, "#{path}[#{i}]")
    end
  end
end
