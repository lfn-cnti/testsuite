require "../spec_helper"

private def run_startup_probe(liveness : String?, startup : String? = nil)
  binary = File.expand_path("./cnti-testsuite")
  dir = File.tempname("cnti-startup-probe", nil)
  Dir.mkdir(dir)
  begin
    installed = File.join(dir, CNF_DIR)
    FileUtils.mkdir_p(File.join(installed, "example"))
    File.write(File.join(installed, "example", "cnti-testsuite.yaml"), <<-YAML)
      config_version: v2
      deployments:
        manifests:
        - name: example
          manifest_directory: manifests
      YAML

    container = {"name" => "app", "image" => "busybox:1.36"} of String => String | YAML::Any
    container["livenessProbe"] = YAML.parse(liveness) if liveness
    container["startupProbe"] = YAML.parse(startup) if startup
    manifest = {
      "apiVersion" => "v1",
      "kind" => "Pod",
      "metadata" => {"name" => "startup-example"},
      "spec" => {"containers" => [container]},
    }
    File.write(File.join(dir, COMMON_MANIFEST_FILE_PATH), manifest.to_yaml)

    output = IO::Memory.new
    status = Process.run(binary, ["startup_probe"], chdir: dir, output: output, error: output,
      env: {"KUBECONFIG" => File.join(dir, "no-cluster")})
    results = File.join(dir, "cnti", "results", "latest.yml")
    File.exists?(results).should(be_true, output.to_s)
    item = YAML.parse(File.read(results))["items"].as_a.find { |entry| entry["name"].as_s == "startup_probe" }
    item.should_not(be_nil, output.to_s)
    {status.exit_code, item.not_nil!["status"].as_s, output.to_s}
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "startup_probe", tags: ["startup_probe"] do
  it "fails and identifies a container that delays liveness without a startup probe" do
    code, verdict, output = run_startup_probe("{exec: {command: ['true']}, initialDelaySeconds: 60}")
    code.should eq(1)
    verdict.should eq("failed")
    output.should contain("Pod/startup-example")
    output.should contain("container app")
    output.should contain("livenessProbe.initialDelaySeconds is 60")
  end

  it "passes the same delayed liveness probe when a startup probe exists" do
    code, verdict, _ = run_startup_probe("{exec: {command: ['true']}, initialDelaySeconds: 60}", "{exec: {command: ['true']}}")
    code.should eq(0)
    verdict.should eq("passed")
  end

  it "passes a liveness probe that omits its initial delay" do
    code, verdict, _ = run_startup_probe("{exec: {command: ['true']}}")
    code.should eq(0)
    verdict.should eq("passed")
  end

  it "is not applicable when the manifest has no liveness probe" do
    code, verdict, _ = run_startup_probe(nil)
    code.should eq(0)
    verdict.should eq("na")
  end
end
