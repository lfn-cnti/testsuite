# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "The CNF test suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s kubectl"
task "cert_compatibility" do |t, args|
  run_cert_category(t, args, "compatibility", "Compatibility, Installability & Upgradability Tests",
    "Compatibility, Installability, and Upgradeability")
end
