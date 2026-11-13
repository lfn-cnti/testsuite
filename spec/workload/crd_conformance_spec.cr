require "../spec_helper"

private def crd_version(name = "v1", storage = true, status = true, schema = "{type: object, properties: {spec: {type: object}}}")
  version = {
    "name" => YAML::Any.new(name), "served" => YAML::Any.new(true), "storage" => YAML::Any.new(storage),
    "schema" => YAML.parse("{openAPIV3Schema: #{schema}}"),
  }
  version["subresources"] = YAML.parse("{status: {}}") if status
  version
end

private def crd_manifest(versions, group = "example.net", kind = "Function", strategy = "None")
  {
    "apiVersion" => "apiextensions.k8s.io/v1",
    "kind"       => "CustomResourceDefinition",
    "metadata"   => {"name" => "#{kind.downcase}s.#{group}"},
    "spec"       => {
      "group" => group, "names" => {"kind" => kind, "plural" => "#{kind.downcase}s"},
      "scope" => "Namespaced", "versions" => versions, "conversion" => {"strategy" => strategy},
    },
  }.to_yaml
end

private def check_crd_conformance(manifest, live : Array(String) = [] of String, unreadable = false)
  binary = File.expand_path("./cnti-testsuite")
  dir = File.tempname("cnti-crd-conformance", nil)
  Dir.mkdir(dir)
  begin
    installed = File.join(dir, CNF_DIR, "example")
    FileUtils.mkdir_p(installed)
    FileUtils.cp("sample-cnfs/sample-batch-workloads/cnti-testsuite.yaml", File.join(installed, "cnti-testsuite.yaml"))
    File.write(File.join(dir, COMMON_MANIFEST_FILE_PATH), manifest)
    File.write(File.join(dir, "live.json"), {"items" => live.map { |definition| YAML.parse(definition) }}.to_json)
    kubectl = File.join(dir, "kubectl")
    File.write(kubectl, <<-SH)
      #!/bin/sh
      if [ "$1 $2" = "get customresourcedefinitions" ]; then
        if [ "$CNTI_SPEC_CRDS_UNREADABLE" = true ]; then
          echo "forbidden to list definitions" >&2
          exit 1
        fi
        cat "$CNTI_SPEC_LIVE_CRDS"
      else
        exit 1
      fi
      SH
    File.chmod(kubectl, 0o755)
    output = IO::Memory.new
    status = Process.run(binary, ["crd_conformance"], chdir: dir, output: output, error: output,
      env: {"PATH" => "#{dir}:#{ENV["PATH"]}", "CNTI_SPEC_LIVE_CRDS" => File.join(dir, "live.json"),
            "CNTI_SPEC_CRDS_UNREADABLE" => unreadable.to_s, "KUBECONFIG" => File.join(dir, "no-cluster")})
    {status.exit_code, output.to_s}
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "crd_conformance", tags: ["crd_conformance"] do
  it "passes a declared CRD with a schema, status subresource and one served storage version" do
    code, output = check_crd_conformance(crd_manifest([crd_version]))
    code.should(eq(0), output)
    output.should contain("PASSED: [crd_conformance]")
  end

  it "fails a permissive schema and identifies the affected version" do
    schema = "{type: object, x-kubernetes-preserve-unknown-fields: true}"
    code, output = check_crd_conformance(crd_manifest([crd_version(schema: schema)]))
    code.should(eq(1), output)
    output.should contain("CustomResourceDefinition/functions.example.net")
    output.should contain("version v1 needs an OpenAPI v3 object schema")
  end

  it "fails a served version without a status subresource" do
    code, output = check_crd_conformance(crd_manifest([crd_version(status: false)]))
    code.should(eq(1), output)
    output.should contain("version v1 has no status subresource")
  end

  it "fails a definition with neither a served nor a storage version" do
    version = crd_version(storage: false)
    version["served"] = YAML::Any.new(false)
    code, output = check_crd_conformance(crd_manifest([version]))
    code.should(eq(1), output)
    output.should contain("no served version is declared")
    output.should contain("expected one storage version, found 0")
  end

  it "fails differing served schemas without conversion" do
    second = crd_version("v2", storage: false, schema: "{type: object, properties: {config: {type: object}}}")
    code, output = check_crd_conformance(crd_manifest([crd_version, second]))
    code.should(eq(1), output)
    output.should contain("different schemas without a conversion webhook")
  end

  it "passes identical schemas served without conversion" do
    code, output = check_crd_conformance(crd_manifest([crd_version, crd_version("v2", storage: false)]))
    code.should(eq(0), output)
    output.should contain("PASSED: [crd_conformance]")
  end

  it "checks the live definition with the exact group and kind and lists platform APIs" do
    manifest = <<-YAML
      apiVersion: example.net/v1
      kind: Function
      metadata: {name: demo}
      ---
      apiVersion: monitoring.coreos.com/v1
      kind: ServiceMonitor
      metadata: {name: monitor}
      YAML
    code, output = check_crd_conformance(manifest, [
      crd_manifest([crd_version]),
      crd_manifest([crd_version(status: false)], kind: "Unrelated"),
      crd_manifest([crd_version(status: false)], group: "monitoring.coreos.com", kind: "ServiceMonitor"),
    ])
    code.should(eq(0), output)
    output.should contain("Checked 1 custom resource definition(s)")
    output.should contain("monitoring.coreos.com/ServiceMonitor: uses a platform API")
  end

  it "skips an unreadable live definition rather than passing" do
    manifest = "apiVersion: example.net/v1\nkind: Function\nmetadata: {name: demo}\n"
    _, output = check_crd_conformance(manifest, unreadable: true)
    output.should contain("SKIPPED: [crd_conformance]")
    output.should contain("forbidden to list definitions")
  end

  it "reports N/A when the CNF uses no CRDs" do
    code, output = check_crd_conformance("apiVersion: v1\nkind: ConfigMap\nmetadata: {name: demo}\n")
    code.should(eq(0), output)
    output.should contain("N/A: [crd_conformance]")
  end
end
