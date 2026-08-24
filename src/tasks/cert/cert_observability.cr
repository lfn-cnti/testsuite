# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "In order to maintain, debug, and have insight into a protected environment, its infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends itself to metrics, tracing, and logging."
task "cert_observability" do |t, args|
  run_cert_category(t, args, "observability", "Observability and Diagnostics Tests",
    "Observability and Diagnostics")
end
