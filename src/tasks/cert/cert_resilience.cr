# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "The CNF test suite checks to see if the CNFs are resilient to failures."
task "cert_resilience" do |t, args|
  run_cert_category(t, args, "resilience", "Reliability, Resilience, and Availability Tests",
    "Reliability, Resilience, and Availability")
end
