# coding: utf-8
require "sam"
require "colorize"
require "file_utils"
require "../utils/utils.cr"

namespace "platform" do
  desc "The CNF test suite checks to see if the CNFs are resilient to failures."
  category_task "resilience", ["worker_reboot_recovery"]

  desc "Does the Platform recover the node and reschedule pods when a worker node fails"
  scored_task "worker_reboot_recovery" do |t, args|
    CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config, result|
      unless check_destructive(args)
        result.skipped("Node not in destructive mode")
        next
      end
      Log.info { "Running POC in destructive mode!" }
      #Select the first node that isn't a master and is also schedulable
      worker_nodes = KubectlClient::Get.worker_nodes
      worker_node = worker_nodes[0]

      FileUtils.mkdir_p(Setup::RENDERED_MANIFESTS_DIR)
      values_manifest = File.join(Setup::RENDERED_MANIFESTS_DIR, "node_failure_values.yml")
      reboot_daemon_manifest = File.join(Setup::RENDERED_MANIFESTS_DIR, "reboot_daemon_pod.yml")
      File.write(values_manifest, NODE_FAILED_VALUES)
      install_coredns = Helm.install("node-failure", "stable/coredns", values: "-f #{values_manifest} --set nodeSelector.\"kubernetes\\.io/hostname\"=#{worker_node}")
      KubectlClient::Wait.resource_wait_for_install("deployment", "node-failure-coredns")

      File.write(reboot_daemon_manifest, REBOOT_DAEMON)
      KubectlClient::Apply.file(reboot_daemon_manifest)
      KubectlClient::Wait.resource_wait_for_install("deployment", "node-failure-coredns")

      begin

        execution_complete = repeat_with_timeout(timeout: POD_READINESS_TIMEOUT, errormsg: "Pod daemon installation has timed-out") do
          pod_ready = KubectlClient::Get.pod_ready?("reboot", "spec.nodeName=#{worker_node}")
          Log.info { "Waiting for reboot daemon to be ready. Current status: #{pod_ready}" }
          pod_ready
        end

        if !execution_complete
          result.failed("Failed to install reboot daemon")
          next
        end

        # Find Reboot Daemon name
        reboot_daemon_pod = KubectlClient::Get.match_pods_by_prefix("reboot", "spec.nodeName=#{worker_node}").first?
        start_reboot = KubectlClient::Utils.exec("#{reboot_daemon_pod}", "touch /tmp/reboot")
        #Watch for Node Failure.
        execution_complete = repeat_with_timeout(timeout: GENERIC_OPERATION_TIMEOUT, errormsg: "Node shut-off has timed-out") do
          pod_ready = KubectlClient::Get.pod_ready?("node-failure")
          node_ready = KubectlClient::Get.node_ready?(worker_node)
          Log.info { "Waiting for Node to go offline..." }
          Log.info { "Pod Ready Status: #{pod_ready}" }
          Log.info { "Node Ready Status: #{node_ready}" }
          !pod_ready || !node_ready
        end

        if !execution_complete
          result.failed("Node failed to go offline")
          next
        end

        #Watch for Node to come back online
        execution_complete = repeat_with_timeout(timeout: NODE_READINESS_TIMEOUT, errormsg: "Node startup has timed-out") do
          pod_ready = KubectlClient::Get.pod_ready?("node-failure")
          node_ready = KubectlClient::Get.node_ready?(worker_node)
          Log.info { "Waiting for Node to come back online..." }
          Log.info { "Pod Ready Status: #{pod_ready}" }
          Log.info { "Node Ready Status: #{node_ready}" }
          pod_ready && node_ready
        end

        if !execution_complete
          result.failed("Node failed to come back online")
          next
        end

        result.passed("Node came back online")
      ensure
        Log.info { "node_failure cleanup" }
        begin
          delete_reboot_daemon = KubectlClient::Delete.file(reboot_daemon_manifest)
        rescue ex: KubectlClient::ShellCMD::NotFoundError
          Log.warn { "Cannot delete file \"#{reboot_daemon_manifest}\". File not found." }
        end
        delete_coredns = Helm.uninstall("node-failure")
        File.delete?(reboot_daemon_manifest)
        File.delete?(values_manifest)
      end
    end
  end
end
