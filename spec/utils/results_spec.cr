require "../spec_helper"
require "../../src/tasks/utils/cli_args_validation"

describe "Results location" do
  it "keeps cnti/results/latest.yml pointing at the newest results file", tags: ["points"] do
    ShellCmd.run_testsuite("_divide_by_zero")
    latest = CNFManager::Points::Results.latest
    File.exists?(latest).should be_true
    newest = Dir.glob("cnti/results/cnti-testsuite-results-*.yml").max_by { |path| File.info(path).modification_time }.not_nil!
    File.symlink?(latest).should be_true
    File.readlink(latest).should eq(File.basename(newest))
    YAML.parse(File.read(latest))["items"].as_a.should_not be_empty
  end

  it "writes to results-dir=PATH, which wins over CNTI_TESTSUITE_RESULTS_DIR", tags: ["points"] do
    cli_dir = File.tempname("results-cli")
    env_dir = File.tempname("results-env")
    begin
      default_count = Dir.glob("cnti/results/cnti-testsuite-results-*.yml").size

      result = ShellCmd.run_testsuite("_divide_by_zero --results-dir #{cli_dir}", "CNTI_TESTSUITE_RESULTS_DIR=#{env_dir}")
      result[:output].should contain("Results: #{cli_dir}/")
      Dir.glob(File.join(cli_dir, "cnti-testsuite-results-*.yml")).size.should eq(1)
      File.exists?(File.join(cli_dir, "latest.yml")).should be_true
      Dir.exists?(env_dir).should be_false
      Dir.glob("cnti/results/cnti-testsuite-results-*.yml").size.should eq(default_count)

      ShellCmd.run_testsuite("_divide_by_zero", "CNTI_TESTSUITE_RESULTS_DIR=#{env_dir}")
      env_files = Dir.glob(File.join(env_dir, "cnti-testsuite-results-*.yml"))
      env_files.size.should eq(1)
      File.readlink(File.join(env_dir, "latest.yml")).should eq(File.basename(env_files.first))

      ShellCmd.run_testsuite("delete_results --results-dir #{cli_dir}")
      Dir.glob(File.join(cli_dir, "*")).should be_empty
    ensure
      FileUtils.rm_rf(cli_dir)
      FileUtils.rm_rf(env_dir)
    end
  end

  it "rejects an empty --results-dir as a usage error", tags: ["points"] do
    result = ShellCmd.run_testsuite("version --results-dir ''")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("Invalid value for '--results-dir'")

    result = ShellCmd.run_testsuite("version --results-dir")
    result[:status].exit_code.should eq(USAGE_EXIT_CODE)
    result[:output].should contain("requires a value")
  end
end
