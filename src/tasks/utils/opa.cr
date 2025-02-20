require "totem"
require "colorize"
require "./cnf_manager.cr"
require "halite"

module OPA
  OPA_KIND_NAME      = "requiretags"
  OPA_VIOLATION_NAME = "block-latest-tag"

  def self.find_non_versioned_pod(pod_name : String) : Bool
    Log.info { "OPA.find_non_versioned_pod: #{pod_name}" }
    violations = KubectlClient::Get.resource(OPA_KIND_NAME, OPA_VIOLATION_NAME).dig("status", "violations").as_a
    matched = violations.any? do |violation|
      begin
        violation.dig("kind").as_s.downcase == "pod" && violation.dig("name").as_s.match(/#{pod_name}/)
      rescue
        false
      end
    end

    Log.info { "OPA Pod Data: #{matched}" }
    matched ? true : false
  end
end
