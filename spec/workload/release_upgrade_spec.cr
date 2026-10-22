require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "file_utils"
require "socket"

# A chart repository for the specs: ./chart packaged in the given versions
# (chart version, app version), indexed and served over HTTP on a free port,
# which the fixture config reads from SPEC_CHART_REPO_PORT.
class SpecChartRepo
  getter dir : String
  getter port : Int32
  @server : Process

  def initialize(versions : Array({String, String}))
    @dir = File.join(Dir.tempdir, "cnti-spec-chart-repo-#{Process.pid}-#{Random.rand(100_000)}")
    Dir.mkdir_p(@dir)
    versions.each do |(version, app_version)|
      ShellCmd.run("helm package sample-cnfs/sample_release_upgrade/chart --version #{version} --app-version #{app_version} -d #{@dir}", force_output: true)[:status].success?.should be_true
    end
    ShellCmd.run("helm repo index #{@dir}", force_output: true)[:status].success?.should be_true
    @port = TCPServer.open("127.0.0.1", 0) { |s| s.local_address.port }
    @server = Process.new("python3", ["-m", "http.server", @port.to_s, "--bind", "127.0.0.1", "--directory", @dir],
      output: Process::Redirect::Close, error: Process::Redirect::Close)
    ok = repeat_with_timeout(15, "chart repository did not open port #{@port}", false, 1) do
      begin
        TCPSocket.new("127.0.0.1", @port).close
        true
      rescue Socket::ConnectError
        false
      end
    end
    ok.should be_true
    ENV["SPEC_CHART_REPO_PORT"] = @port.to_s
  end

  def close
    @server.terminate rescue nil
    @server.wait rescue nil
    FileUtils.rm_rf(@dir)
    ShellCmd.run("helm repo remove cnti-spec-release", force_output: true)
  end
end

def installed_chart_version(release : String) : String?
  Helm.release_status(release, DEFAULT_CNF_NAMESPACE).try { |s| s["chart"]?.try(&.as_s?) }
end

def release_revision(release : String) : Int32
  Helm.release_status(release, DEFAULT_CNF_NAMESPACE).try { |s| s["revision"]?.try(&.as_s?).try(&.to_i?) } || 0
end

describe "Release upgrade", tags: ["release_upgrade"] do
  it "'rolling_update' moves a chart from a repository to the release before and upgrades it back, preferring a release with another app version" do
    # 0.1.5 ships the same app version as the installed 0.2.0: a chart-only
    # change, so the release before is 0.1.0.
    repo = SpecChartRepo.new([{"0.1.0", "1.36.1"}, {"0.1.5", "1.37.0"}, {"0.2.0", "1.37.0"}])
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_release_upgrade/cnti-testsuite.yaml")
      installed_chart_version("sample-release").should eq("sample-release-0.2.0")
      result = ShellCmd.run_testsuite("rolling_update")
      result[:status].success?.should be_true
      (/chart sample-release \(sample-release 0\.2\.0\): no previous_chart_version configured, using 0\.1\.0, the release before \(0\.1\.5 ships the same app version 1\.37\.0 as the installed chart\)/ =~ result[:output]).should_not be_nil
      (/chart sample-release \(sample-release 0\.2\.0\): 0\.1\.0, then 0\.2\.0: every workload of the release rolled out/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "passed")
      # Back at the version under test, through two helm upgrades.
      installed_chart_version("sample-release").should eq("sample-release-0.2.0")
      release_revision("sample-release").should eq(3)
      image = KubectlClient::Get.resource("deployment", "sample-release-app", DEFAULT_CNF_NAMESPACE).dig("spec", "template", "spec", "containers", 0, "image").as_s
      image.should eq("busybox:1.37.0")
    ensure
      ShellCmd.cnf_uninstall
      repo.close
    end
  end

  it "'rolling_downgrade' and 'rollback' move the release and bring it back" do
    repo = SpecChartRepo.new([{"0.1.0", "1.36.1"}, {"0.2.0", "1.37.0"}])
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_release_upgrade/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_downgrade")
      result[:status].success?.should be_true
      (/chart sample-release \(sample-release 0\.2\.0\): 0\.1\.0: every workload of the release rolled out/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_downgrade", "passed")
      installed_chart_version("sample-release").should eq("sample-release-0.2.0")

      result = ShellCmd.run_testsuite("rollback")
      result[:status].success?.should be_true
      (/chart sample-release \(sample-release 0\.2\.0\): moved to 0\.1\.0, then rolled back to 0\.2\.0 with helm rollback: every workload of the release rolled out/ =~ result[:output]).should_not be_nil
      verify_task_result("rollback", "passed")
      installed_chart_version("sample-release").should eq("sample-release-0.2.0")
    ensure
      ShellCmd.cnf_uninstall
      repo.close
    end
  end

  it "'rolling_update' is skipped with a remediation when the repository lists no release before the installed one" do
    repo = SpecChartRepo.new([{"0.2.0", "1.37.0"}])
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_release_upgrade/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_update")
      (/SKIPPED.*No usable rolling_update_test_tag configured for any container, and no previous release to take from the registry/ =~ result[:output]).should_not be_nil
      (/remediation: No previous_chart_version configured for chart sample-release, and no release before 0\.2\.0 is listed for sample-release: set previous_chart_version to an older released version/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "skipped")
      release_revision("sample-release").should eq(1)
    ensure
      ShellCmd.cnf_uninstall
      repo.close
    end
  end

  it "'rolling_update' reports a previous image that does not start under the current pod spec as version skew, not as a failed rollout" do
    begin
      ShellCmd.cnf_install("--cnf-config ./sample-cnfs/sample_rolling_skew/cnti-testsuite.yaml")
      result = ShellCmd.run_testsuite("rolling_update")
      (/N\/A.*Every workload of the CNF has a previous image that does not start under the current pod spec \(version skew, see the details\), a rolling update does not apply/ =~ result[:output]).should_not be_nil
      (/Deployment\/skew in cnti-default, container app: version skew, python:3\.11-slim \(the release before the deployed one\) does not start under the pod spec the current chart renders \(.*CrashLoopBackOff.*\); not judged/ =~ result[:output]).should_not be_nil
      verify_task_result("rolling_update", "na")
      # And the deployed image is back.
      deployment = KubectlClient::Get.resource("deployment", "skew", DEFAULT_CNF_NAMESPACE)
      deployment.dig("spec", "template", "spec", "containers", 0, "image").as_s.should eq("python:3.12-slim")
    ensure
      ShellCmd.cnf_uninstall
    end
  end
end
