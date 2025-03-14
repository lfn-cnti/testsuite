# coding: utf-8
require "sam"
require "colorize"
require "../utils/utils.cr"

namespace "platform" do
  desc "The CNF container should access all hardware and schedule to specific worker nodes by using a device plugin."
  task "hardware_and_scheduling", ["oci_compliant"] do |t, args|
    Log.debug { "hardware_and_scheduling" }
    Log.trace { "hardware_and_scheduling args.raw: #{args.raw}" }
    Log.trace { "hardware_and_scheduling args.named: #{args.named}" }
    stdout_score("platform:hardware_and_scheduling")
  end

  desc "Does the Platform use a runtime that is oci compliant"
  task "oci_compliant" do |t, args|
    task_response = CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args|
      resp = KubectlClient::Get.container_runtimes
      all_oci_runtimes = true
      resp.each do |x|
        if (x =~ KubectlClient::OCI_RUNTIME_REGEX).nil?
          all_oci_runtimes = false
        end
      end
      Log.info { "all_oci_runtimes: #{all_oci_runtimes}" }
      if all_oci_runtimes
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Your platform is using the following runtimes: [#{KubectlClient::Get.container_runtimes.join(",")}] which are OCI compliant runtimes")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Platform has at least one node that uses a non OCI compliant runtime")
      end
    end
  end
end
