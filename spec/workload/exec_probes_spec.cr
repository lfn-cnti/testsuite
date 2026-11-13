require "../spec_helper"

private def check_exec_probes(containers)
  binary = File.expand_path("./cnti-testsuite")
  dir = File.tempname("cnti-exec-probes", nil)
  Dir.mkdir(dir)
  begin
    manifest = <<-YAML
      apiVersion: v1
      kind: Pod
      metadata:
        name: probe-example
      spec:
        containers:
      #{containers.to_yaml.lines.skip(1).map { |line| "    #{line}" }.join("\n")}
      YAML
    installed = File.join(dir, CNF_DIR, "example")
    FileUtils.mkdir_p(installed)
    FileUtils.cp("sample-cnfs/sample-batch-workloads/cnti-testsuite.yaml", File.join(installed, "cnti-testsuite.yaml"))
    File.write(File.join(dir, COMMON_MANIFEST_FILE_PATH), manifest)
    output = IO::Memory.new
    status = Process.run(binary, ["exec_probes"],
      chdir: dir, output: output, error: output, env: {"KUBECONFIG" => File.join(dir, "no-cluster")})
    {status.exit_code, output.to_s}
  ensure
    FileUtils.rm_rf(dir)
  end
end

private def probe_container(name = "app", probe = nil, resources = nil, probe_type = "livenessProbe")
  container = {"name" => YAML::Any.new(name), "image" => YAML::Any.new("busybox:1.36")}
  container[probe_type] = YAML.parse(probe) if probe
  container["resources"] = YAML.parse(resources) if resources
  container
end

describe "exec_probes", tags: ["exec_probes"] do
  cpu_limits = "{limits: {cpu: '1000m', memory: 64Mi}, requests: {cpu: 1}}"
  slow_exec = "{exec: {command: ['true']}, periodSeconds: 30}"

  it "passes a TCP probe on a container eligible for exclusive CPUs" do
    code, output = check_exec_probes([probe_container(probe: "{tcpSocket: {port: 8080}}", resources: cpu_limits)])
    code.should(eq(0), output)
    output.should contain("PASSED: [exec_probes]")
  end

  it "fails an exec probe on a container eligible for exclusive CPUs" do
    code, output = check_exec_probes([probe_container(probe: slow_exec, resources: cpu_limits, probe_type: "startupProbe")])
    code.should(eq(1), output)
    output.should contain("container app")
    output.should contain("startupProbe uses exec and container is eligible for exclusive CPUs")
  end

  it "passes a 30-second exec probe on a container without exclusive CPU eligibility" do
    code, output = check_exec_probes([probe_container(probe: slow_exec)])
    code.should(eq(0), output)
    output.should contain("PASSED: [exec_probes]")
  end

  it "passes a default-period exec probe when another container makes the pod Burstable" do
    probe = "{exec: {command: ['true']}}"
    code, output = check_exec_probes([probe_container(probe: probe, resources: cpu_limits), probe_container(name: "helper")])
    code.should(eq(0), output)
    output.should contain("PASSED: [exec_probes]")
  end

  it "fails when the CNF declares eleven exec probes" do
    containers = (1..11).map { |index| probe_container(name: "app-#{index}", probe: slow_exec) }
    code, output = check_exec_probes(containers)
    code.should(eq(1), output)
    output.should contain("11 exec probes, above the limit of 10")
  end

  it "fails an exec probe with a five-second period" do
    code, output = check_exec_probes([probe_container(probe: "{exec: {command: ['true']}, periodSeconds: 5}", probe_type: "readinessProbe")])
    code.should(eq(1), output)
    output.should contain("readinessProbe uses exec and periodSeconds is 5")
  end

  it "reports N/A when the manifest has no probes" do
    code, output = check_exec_probes([probe_container])
    code.should(eq(0), output)
    output.should contain("N/A: [exec_probes]")
  end
end
