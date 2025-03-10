require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"

describe "Security" do

  it "'privileged_containers' should pass with a non-privileged cnf", tags: ["privileges"]  do
    begin
      ShellCmd.cnf_install("cnf-config=sample-cnfs/sample-statefulset-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("privileged_containers")
      result[:status].success?.should be_true
      (/No privileged containers/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      Log.debug { result[:output] }
    end
  end
  it "'privileged_containers' should fail on a non-whitelisted, privileged cnf", tags: ["privileges"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_privileged_cnf/cnf-testsuite.yml skip_wait_for_install")
      result = ShellCmd.run_testsuite("privileged_containers")
      result[:status].success?.should be_true
      (/Found.*privileged containers.*/ =~ result[:output]).should_not be_nil
      (/Privileged container (privileged-coredns) in.*/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'privileged_containers' should pass on a whitelisted, privileged cnf", tags: ["privileges"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_whitelisted_privileged_cnf/cnf-testsuite.yml skip_wait_for_install")
      result = ShellCmd.run_testsuite("privileged_containers")
      result[:status].success?.should be_true
      (/No privileged containers/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'privilege_escalation' should fail on a cnf that has escalated privileges", tags: ["privileges"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-privilege-escalation/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("privilege_escalation")
      result[:status].success?.should be_true
      (/(PASSED).*(No containers that allow privilege escalation were found)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'privilege_escalation' should pass on a cnf that does not have escalated privileges", tags: ["privileges"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-nonroot-containers/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("privilege_escalation")
      result[:status].success?.should be_true
      (/(PASSED).*(No containers that allow privilege escalation were found)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'symlink_file_system' should pass on a cnf that does not allow a symlink attack", tags: ["capabilities"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-privilege-escalation/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("symlink_file_system")
      result[:status].success?.should be_true
      (/(PASSED).*(No containers allow a symlink attack)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'insecure_capabilities' should pass on a cnf that does not have containers with insecure capabilities", tags: ["capabilities"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("insecure_capabilities")
      result[:status].success?.should be_true
      (/(PASSED).*(Containers with insecure capabilities were not found)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'insecure_capabilities' should fail on a cnf that has containers with insecure capabilities", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-insecure-capabilities/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("insecure_capabilities")
      result[:status].success?.should be_true
      (/(PASSED).*(Containers with insecure capabilities were not found)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'linux_hardening' should fail on a cnf that does not make use of security services", tags: ["capabilities"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("linux_hardening")
      result[:status].success?.should be_true
      (/(PASSED).*(Security services are being used to harden applications)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'application_credentials' should fail on a cnf that allows applications credentials in configuration files", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-appliciation-credentials/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("application_credentials")
      result[:status].success?.should be_true
      (/(FAILED).*(Found applications credentials in configuration files)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'host_network' should pass on a cnf that does not have a host network attached to pod", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-privilege-escalation/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("host_network")
      result[:status].success?.should be_true
      (/(PASSED).*(No host network attached to pod)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'service_account_mapping' should fail on a cnf that automatically maps the service account", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-service-accounts/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("service_account_mapping")
      result[:status].success?.should be_true
      (/(FAILED).*(Service accounts automatically mapped)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'cpu_limits' should pass on a cnf that has containers with cpu limits set", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("cpu_limits")
      result[:status].success?.should be_true
      (/(PASSED).*(Containers have CPU limits set)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'memory_limits' should pass on a cnf that has containers with memory limits set", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("memory_limits")
      result[:status].success?.should be_true
      (/(PASSED).*(Containers have memory limits set)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'ingress_egress_blocked' should fail on a cnf that has no ingress and egress traffic policy", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("ingress_egress_blocked")
      result[:status].success?.should be_true
      (/(PASSED).*(Ingress and Egress traffic blocked on pods)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'host_pid_ipc_privileges' should pass on a cnf that does not have containers with host PID/IPC privileges", tags: ["capabilities"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("host_pid_ipc_privileges")
      result[:status].success?.should be_true
      (/(FAILED).*(Found containers with hostPID and hostIPC privileges)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'non_root_containers' should pass on a cnf that does not have containers running with root user or user with root group memberships", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-nonroot")
      result = ShellCmd.run_testsuite("non_root_containers")
      result[:status].success?.should be_true
      (/(FAILED).*(Found containers running with root user or user with root group membership)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'non_root_containers' should fail on a cnf that has containers running with root user or user with root group memberships", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("non_root_containers")
      result[:status].success?.should be_true
      (/(PASSED).*(Containers are running with non-root user with non-root group membership)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'immutable_file_systems' should fail when the cnf containers with mutable file systems", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      result = ShellCmd.run_testsuite("immutable_file_systems")
      result[:status].success?.should be_true
      (/(PASSED).*(Containers have immutable file systems)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'immutable_file_systems' should pass when the cnf containers with immutable file systems", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-immutable-fs")
      result = ShellCmd.run_testsuite("immutable_file_systems")
      result[:status].success?.should be_true
      (/(PASSED).*(Containers have immutable file systems)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'hostpath_mounts' should pass when the cnf has no containers with hostPath mounts", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-coredns-cnf")
      ClusterTools.uninstall
      result = ShellCmd.run_testsuite("hostpath_mounts")
      result[:status].success?.should be_true
      (/(FAILED).*(Found containers with hostPath mounts)/ =~ result[:output]).should be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      ClusterTools.install
    end
  end

  it "'hostpath_mounts' should fail when the cnf has containers with hostPath mounts", tags: ["security"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-hostpath")
      ClusterTools.uninstall
      result = ShellCmd.run_testsuite("hostpath_mounts")
      result[:status].success?.should be_true
      (/(FAILED).*(Found containers with hostPath mounts)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      ClusterTools.install
    end
  end

  it "'container_sock_mounts' should pass if a cnf has no pods that mount container engine socket", tags: ["container_sock_mounts"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_coredns/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("container_sock_mounts")
      result[:status].success?.should be_true
      (/(PASSED).*(Container engine daemon sockets are not mounted as volumes)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'container_sock_mounts' should fail if the CNF has pods with container engine sockets mounted", tags: ["container_sock_mounts"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_container_sock_mount/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("container_sock_mounts")
      result[:status].success?.should be_true
      (/(FAILED).*(Container engine daemon sockets are mounted as volumes)/ =~ result[:output]).should_not be_nil
      (/Unix socket is not allowed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'external_ips' should pass if a cnf has no services with external IPs", tags: ["external_ips"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_coredns/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("external_ips")
      result[:status].success?.should be_true
      (/(PASSED).*(Services are not using external IPs)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'external_ips' should fail if a cnf has services with external IPs", tags: ["external_ips"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_external_ips/cnf-testsuite.yml")
      result = ShellCmd.run_testsuite("external_ips")
      result[:status].success?.should be_true
      (/(FAILED).*(Services are using external IPs)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'selinux_options' should fail if containers have custom selinux options that can be used for privilege escalations", tags: ["selinux_options"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_latest_tag")
      result = ShellCmd.run_testsuite("selinux_options")
      result[:status].success?.should be_true
      (/(FAILED).*(Pods are using custom SELinux options that can be used for privilege escalations)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'selinux_options' should be skipped if containers do not use custom selinux options", tags: ["selinux_options"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_nonroot")
      result = ShellCmd.run_testsuite("selinux_options")
      result[:status].success?.should be_true
      (/(N\/A).*(Pods are not using SELinux)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'selinux_options' should pass if containers do not have custom selinux options that can be used for privilege escalations", tags: ["selinux_options"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_valid_selinux_options")
      result = ShellCmd.run_testsuite("selinux_options")
      result[:status].success?.should be_true
      (/(PASSED).*(Pods are not using custom SELinux options that can be used for privilege escalations)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'sysctls' should fail if Pods have restricted sysctls values", tags: ["sysctls"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_sysctls")
      result = ShellCmd.run_testsuite("sysctls")
      result[:status].success?.should be_true
      (/(FAILED).*(Restricted values for are being used for sysctls)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'sysctls' should pass if Pods have allowed sysctls values", tags: ["sysctls"] do
    begin
      ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample_nonroot")
      result = ShellCmd.run_testsuite("sysctls")
      result[:status].success?.should be_true
      (/(PASSED).*(No restricted values found for sysctls)/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end
end
