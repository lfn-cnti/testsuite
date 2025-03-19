# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../../modules/kubectl_client"


task "divide_by_zero" do |_, args|
  CNFManager::Task.task_runner(args, check_cnf_installed: false) do |args, config|
    Log.info {"divide by zero"}
    raise "divide by zero" 
    "divided by zero" 
  end
end
