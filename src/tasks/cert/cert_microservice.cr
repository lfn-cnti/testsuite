# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../../modules/docker_client"
require "halite"
require "totem"
require "./cert_utils.cr"

desc "The CNF test suite checks to see if CNFs follows microservice principles"
task "cert_microservice" do |t, args|
  run_cert_category(t, args, "microservice", "Microservice Tests")
end
