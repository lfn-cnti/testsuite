require "../spec_helper"

describe "RunLog" do
  it "writes one entry per line, with the test's name and indented continuation lines", tags: ["points"] do
    io = IO::Memory.new
    Log.with_context do
      Log.context.set(test: "node_drain")
      entry = Log::Entry.new("KubectlClient", :debug, "first line\n[second] line", Log::Metadata.empty, nil)
      RunLog.format(entry, io)
    end
    RunLog.format(Log::Entry.new("", :info, "outside a test", Log::Metadata.empty, nil), io)

    lines = io.to_s.lines
    lines.size.should eq(3)
    lines[0].should match(/^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} [+-]\d\d:\d\d\] DEBUG test=node_drain -- CNTI-KubectlClient: first line$/)
    lines[1].should eq("  [second] line")
    lines[2].should match(/^\[.*\]  INFO -- CNTI: outside a test$/)
  end

  it "moves the logs waiting in pending/ into the run's directory", tags: ["points"] do
    dir = File.tempname("run-log")
    begin
      pending = File.join(dir, RunLog::PENDING_DIR)
      FileUtils.mkdir_p(pending)
      File.write(File.join(pending, "setup-20261029-100000-000.log"), "setup\n")
      File.write(File.join(pending, "cnf_install-20261029-100100-000.log"), "install\n")
      run_dir = File.join(dir, "cnti-testsuite-results-20261029-100200-000")
      FileUtils.mkdir_p(run_dir)

      RunLog.adopt_pending(dir, run_dir)

      File.read(File.join(run_dir, "cnf_install-20261029-100100-000.log")).should eq("install\n")
      File.read(File.join(run_dir, "setup-20261029-100000-000.log")).should eq("setup\n")
      Dir.exists?(pending).should be_false
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "keeps the newest run directories and every results file", tags: ["points"] do
    dir = File.tempname("run-log")
    begin
      FileUtils.mkdir_p(dir)
      stamps = ["20261027-090000-000", "20261028-090000-000", "20261029-090000-000"]
      stamps.each do |stamp|
        FileUtils.mkdir_p(File.join(dir, "cnti-testsuite-results-#{stamp}"))
        File.write(File.join(dir, "cnti-testsuite-results-#{stamp}.yml"), "items: []\n")
      end

      RunLog.prune(dir, 2)

      Dir.exists?(File.join(dir, "cnti-testsuite-results-#{stamps[0]}")).should be_false
      Dir.exists?(File.join(dir, "cnti-testsuite-results-#{stamps[1]}")).should be_true
      Dir.exists?(File.join(dir, "cnti-testsuite-results-#{stamps[2]}")).should be_true
      stamps.each { |stamp| File.exists?(File.join(dir, "cnti-testsuite-results-#{stamp}.yml")).should be_true }
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "keeps a debug log of every run next to its results file, at the console's default level", tags: ["points"] do
    dir = File.tempname("results-run-log")
    begin
      result = ShellCmd.run_testsuite("_debug_log_in_test", "CNTI_TESTSUITE_RESULTS_DIR=#{dir} CNTI_TESTSUITE_LOG_LEVEL=error")
      result[:output].should_not contain("debug entry inside a test")
      results_file = Dir.glob(File.join(dir, "cnti-testsuite-results-*.yml")).first
      log = File.read(File.join(RunLog.run_dir_for(results_file), RunLog::FILE_NAME))
      log.should match(/^\[.*\]  INFO test=_debug_log_in_test -- CNTI-CNFManager.Task.task_runner._debug_log_in_test: Starting test$/m)
      log.should match(/^\[.*\] DEBUG test=_debug_log_in_test -- CNTI-mock: debug entry inside a test$/m)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "gives the next run the log of a cnf_install run before it, and keeps CNTI_TESTSUITE_KEEP_RUNS runs", tags: ["points"] do
    dir = File.tempname("results-run-log")
    empty_config_dir = File.tempname("no-cnf-config")
    begin
      FileUtils.mkdir_p(empty_config_dir)
      # Stops once the task runs, with nothing to install: the log waits all the same.
      result = ShellCmd.run_testsuite("cnf_install --cnf-config #{empty_config_dir}", "CNTI_TESTSUITE_RESULTS_DIR=#{dir}")
      result[:status].success?.should be_false
      pending = Dir.glob(File.join(dir, RunLog::PENDING_DIR, "cnf_install-*.log"))
      pending.size.should eq(1)
      File.read(pending.first).should contain("CNTI-Setup.")

      ShellCmd.run_testsuite("_divide_by_zero", "CNTI_TESTSUITE_RESULTS_DIR=#{dir} CNTI_TESTSUITE_KEEP_RUNS=1")
      first_run = Dir.glob(File.join(dir, RunLog::RUN_DIR_GLOB)).select { |path| Dir.exists?(path) }
      first_run.size.should eq(1)
      File.exists?(File.join(first_run.first, File.basename(pending.first))).should be_true
      Dir.exists?(File.join(dir, RunLog::PENDING_DIR)).should be_false

      ShellCmd.run_testsuite("_divide_by_zero", "CNTI_TESTSUITE_RESULTS_DIR=#{dir} CNTI_TESTSUITE_KEEP_RUNS=1")
      runs = Dir.glob(File.join(dir, RunLog::RUN_DIR_GLOB)).select { |path| Dir.exists?(path) }
      runs.size.should eq(1)
      runs.should_not eq(first_run)
      Dir.glob(File.join(dir, "cnti-testsuite-results-*.yml")).size.should eq(2)
    ensure
      FileUtils.rm_rf(dir) if dir
      FileUtils.rm_rf(empty_config_dir) if empty_config_dir
    end
  end
end
