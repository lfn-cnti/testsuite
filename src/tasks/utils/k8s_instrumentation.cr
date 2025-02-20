require "totem"
require "colorize"
require "./cnf_manager.cr"
require "halite"


module K8sInstrumentation
  def self.disk_speed
    cluster_tools_pod = KubectlClient::Get.match_pods_by_prefix("cluster-tools", namespace: TESTSUITE_NAMESPACE).first
    result = ShellCmd.run("kubectl get all -A", "k8s_instrumentation_debug", force_output: true)
    resp = KubectlClient::Utils.exec(cluster_tools_pod, "/bin/bash -c 'sysbench fileio prepare && sysbench fileio --file-test-mode=rndrw run'", namespace: TESTSUITE_NAMESPACE)
    parse_sysbench(resp[:output].to_s)
  end

  def self.parse_sysbench(sysbench_output)
    parsed_output = sysbench_output.split("\n").reduce(Hash(String, String).new) do |acc,x| 
      if (x.match(/(.*):(.*)/).try &.[1])
        acc.merge({"#{(x.match(/(.*):(.*)/).try &.[1])}".strip => "#{x.match(/(.*):(.*)/).try &.[2]}".strip})
      else
        acc
      end
    end
    Log.debug { "parsed_output: #{parsed_output}" }
    parsed_output
  end
end
