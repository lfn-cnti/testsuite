# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../../modules/kubectl_client"


task "_divide_by_zero" do |_, args|
  CNFManager::Task.task_runner(args, check_cnf_installed: false) do |args, config, result|
    Log.info {"divide by zero"}
    raise "divide by zero" 
    "divided by zero" 
  end
end

# _divide_by_zero as a named test: one debug entry logged while it runs, for
# the run log's specs (the entry carries the test's name).
task "_debug_log_in_test" do |t, args|
  CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config, result|
    Log.for("mock").debug { "debug entry inside a test" }
    raise "divide by zero"
  end
end

# Raises outside task_runner, so nothing catches it before the entrypoint's
# last-resort rescue. Exercises the "the suite itself broke" exit code.
task "_raise_outside_task_runner" do |_, args|
  raise "unhandled"
end
