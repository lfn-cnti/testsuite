require "../spec_helper"
require "./schema_validator"

# docs/cnti-testsuite-config.schema.json describes what the configuration
# parser accepts, so that an editor or an AI agent can write a valid
# cnti-testsuite.yaml without installing anything. These examples keep the two
# in agreement: every v2 configuration the repository ships passes both, and
# each broken one below fails both. A field added to the parser without the
# schema, or the other way round, fails here.
private def config_schema : JSON::Any
  JSON.parse(File.read("docs/cnti-testsuite-config.schema.json"))
end

private def schema_valid?(yaml : String) : Bool
  schema = config_schema
  validate_against_schema(YAML.parse(yaml), schema, schema["$defs"])
  true
rescue
  false
end

private def parser_valid?(yaml : String) : Bool
  CNFInstall::Config.parse_cnf_config_from_yaml(CNFInstall::Config.render_jinja_template(yaml))
  true
rescue
  false
end

describe "cnti-testsuite.yaml schema" do
  it "accepts every v2 configuration the repository ships, as the parser does", tags: ["points"] do
    files = Dir.glob("sample-cnfs/**/cnti-testsuite*.y{,a}ml") + Dir.glob("example-cnfs/**/cnti-testsuite*.y{,a}ml")
    v2 = files.select { |f| File.read(f) =~ /^config_version:\s*"?v2"?\s*$/m }
    v2.size.should be > 100
    v2.each do |file|
      yaml = File.read(file)
      {file, parser_valid?(yaml)}.should eq({file, true})
      schema = config_schema
      validate_against_schema(YAML.parse(yaml), schema, schema["$defs"], file)
    end
  end

  it "rejects what the parser rejects", tags: ["points"] do
    chart_dir = "config_version: v2\ndeployments:\n  helm_dirs:\n    - name: web\n      helm_directory: chart\n"
    {
      "a valid minimal configuration" => {chart_dir, true},
      "an unknown top-level key"      => {chart_dir + "extra: 1\n", false},
      "an unknown deployment key"     => {chart_dir + "      helm_dir: chart\n", false},
      "a deployment without its directory" =>
        {"config_version: v2\ndeployments:\n  helm_dirs:\n    - name: web\n", false},
      "a priority that is not a number" => {chart_dir + "      priority: first\n", false},
      "an image size limit below one"   => {chart_dir + "common:\n  image_size_max_mb: 0\n", false},
      "a container entry with an unknown key" =>
        {chart_dir + "common:\n  container_names:\n    - name: web\n      rolling_update_tag: \"2\"\n", false},
      "a typo in auth_defaults" =>
        {chart_dir + "common:\n  auth_defaults:\n    helm_repos:\n      cm:\n        user: me\n", false},
    }.each do |what, (yaml, valid)|
      {what, parser_valid?(yaml)}.should eq({what, valid})
      {what, schema_valid?(yaml)}.should eq({what, valid})
    end
  end
end
