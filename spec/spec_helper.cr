require "spec"
require "colorize"
require "../src/cnf_testsuite"
require "../src/tasks/utils/utils.cr"
require "../src/modules/tar/tar.cr"
require "../src/modules/git/git.cr"
require "../src/modules/release_manager/release_manager.cr"
require "../src/modules/kernel_introspection/kernel_introspection.cr"
require "../src/modules/docker_client/docker_client.cr"
require "../src/modules/helm/helm.cr"
require "../src/modules/kernel_introspection/k8s.cr"

ENV["CRYSTAL_ENV"] = "TEST" 


Log.info { "Building ./cnf-testsuite".colorize(:green) }
result = ShellCmd.run("crystal build --warnings none src/cnf-testsuite.cr")
if result[:status].success?
  Log.info { "Build Success!".colorize(:green) }
else
  Log.info { "crystal build failed!".colorize(:red) }
  raise "crystal build failed in spec_helper"
end

module ShellCmd
  def self.run_testsuite(testsuite_cmd, cmd_prefix="")
    cmd = "#{cmd_prefix} ./cnf-testsuite #{testsuite_cmd}"
    run(cmd, log_prefix: "ShellCmd.run_testsuite", force_output: true, joined_output: true)
  end

  def self.cnf_install(install_params, cmd_prefix="", expect_failure=false)
    timeout_parameter = install_params.includes?("timeout") ? "" : "timeout=300"
    result = run_testsuite("cnf_install #{install_params} #{timeout_parameter}", cmd_prefix)
    if !expect_failure
      result[:status].success?.should be_true
    else
      result[:status].success?.should be_false
    end
    result
  end

  def self.cnf_uninstall(uninstall_params="", cmd_prefix="", expect_failure=false)
    timeout_parameter = uninstall_params.includes?("timeout") ? "" : "timeout=300"
    result = run_testsuite("cnf_uninstall #{uninstall_params} #{timeout_parameter}", cmd_prefix)
    if !expect_failure
      result[:status].success?.should be_true
    else
      result[:status].success?.should be_false
    end
    result
  end
end
