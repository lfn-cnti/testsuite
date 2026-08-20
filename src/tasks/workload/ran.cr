# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "The CNF test suite checks to see if RAN CNFs follow cloud native principles"
category_task "ran", ["oran_e2_connection"]
desc "Test if RAN uses the ORAN e2 interface"
scored_task "oran_e2_connection" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    if ORANMonitor.isCNFaRIC?(config)
      # (kosstennbl) TODO: Redesign oran_e2_connection test, preferably without usage of installation configmaps. More info in issue #2153
      result.skipped("oran_e2_connection test is disabled, check #2153")
    else
      result.na("[oran_e2_connection] No ric designated in cnf_testsuite.yml")
    end
  end

end
