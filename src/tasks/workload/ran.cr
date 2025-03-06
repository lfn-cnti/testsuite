# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "The CNF test suite checks to see if RAN CNFs follow cloud native principles"
task "ran", ["oran_e2_connection"] do |_, args|
  stdout_score("ran")
  case "#{ARGV.join(" ")}" 
  when /ran/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end
desc "Test if RAN uses the ORAN e2 interface"
task "oran_e2_connection" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    if ORANMonitor.isCNFaRIC?(config)
      # (kosstennbl) TODO: Redesign oran_e2_connection test, preferably without usage of installation configmaps. More info in issue #2153
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "oran_e2_connection test is disabled, check #2153")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::NA, "[oran_e2_connection] No ric designated in cnf_testsuite.yml")
    end
  end

end
