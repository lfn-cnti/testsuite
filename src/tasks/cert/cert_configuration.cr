# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "json"
require "../utils/utils.cr"
require "./cert_utils.cr"

desc "Configuration should be managed in a declarative manner, using ConfigMaps, Operators, or other declarative interfaces."

task "cert_configuration" do |t, args|
  run_cert_category(t, args, "configuration", "Configuration Tests")
end
