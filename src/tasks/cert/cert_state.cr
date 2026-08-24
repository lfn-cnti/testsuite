# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../../modules/kubectl_client"
require "./cert_utils.cr"

desc "The CNF test suite checks if state is stored in a custom resource definition or a separate database (e.g. etcd) rather than requiring local storage.  It also checks to see if state is resilient to node failure"
task "cert_state" do |t, args|
  run_cert_category(t, args, "state", "State Tests")
end
