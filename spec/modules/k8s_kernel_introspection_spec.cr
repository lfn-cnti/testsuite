require "../spec_helper.cr"

describe "KernelIntrospection" do
  before_all do
    KubectlClient::AssureApplied.namespace("cnf-testsuite")
    ClusterTools.install
  end

  it "'#status_by_proc' should return all statuses for all containers in a pod", tags:["k8s_kernel_introspection"] do
    result = KubectlClient::ShellCMD.run("kubectl run nginx --image=nginx --labels='name=nginx'")
    pods = KubectlClient::Get.pods_by_nodes(KubectlClient::Get.schedulable_nodes_list)
    pods.should_not be_nil
    pods = KubectlClient::Get.pods_by_labels(pods, {"name" => "nginx"})
    pods.should_not be_nil

    KubectlClient::Wait.resource_wait_for_install("pod", "nginx")
    pods.size.should be > 0
    first_node = pods[0]
    statuses = KernelIntrospection::K8s.status_by_proc(first_node.dig("metadata", "name"), "nginx")
    Log.info { "process-statuses: #{statuses}" }
    (statuses).should_not be_nil

    (statuses.find{|x| x["cmdline"].includes?("nginx: master process")} ).should_not be_nil

    KubectlClient::Delete.resource("pod", "nginx")
  end

  it "'#find_first_process' should return first matching process", tags:["k8s_kernel_introspection"] do
    result = KubectlClient::ShellCMD.run("kubectl run nginx --image=nginx --labels='name=nginx'")
    KubectlClient::Wait.resource_wait_for_install("pod", "nginx")
    begin
      pod_info = KernelIntrospection::K8s.find_first_process("nginx: master process")
      Log.info { "pod_info: #{pod_info}"}
      (pod_info).should_not be_nil
    ensure
      KubectlClient::Delete.resource("pod", "nginx")
    end
  end

  it "'#find_matching_processes' should return all matching processes", tags:["k8s_kernel_introspection"] do
    result = KubectlClient::ShellCMD.run("kubectl run nginx --image=nginx --labels='name=nginx'")
    KubectlClient::Wait.resource_wait_for_install("pod", "nginx")
    begin
      pods_info = KernelIntrospection::K8s.find_matching_processes("nginx")
      Log.info { "pods_info: #{pods_info}"}
      (pods_info).size.should be > 0
    ensure
      KubectlClient::Delete.resource("pod", "nginx")
    end
  end

end