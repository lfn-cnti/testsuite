require "../../modules/cluster_tools"
require "./k8s_tshark.cr"
module ORANMonitor 

  def self.isCNFaRIC?(config)
    Log.info { "isCNFaRIC?" }
    ric_label = config.common.five_g_parameters.ric_label
    Log.info { "ric: #{ric_label}" }
    if !ric_label.nil? && !ric_label.empty?
      ric_key = ric_label.split("=").first
      ric_value = ric_label.split("=").last
      Log.info { "cnf is a ric" }
      ret = {:ric_key => ric_key, :ric_value => ric_value}
    else
      Log.info { "cnf not a ric" }
     ret = nil
    end 
    ret
  end
  
  def self.start_e2_capture?(config)
    Log.info { "start_e2_capture" }
    capture : K8sTshark::TsharkPacketCapture | Nil
    ric = isCNFaRIC?(config)
    if ric
      ric_key = ric[:ric_key]
      ric_value = ric[:ric_value]
      command = "-i any -f 'sctp port 36421' -d 'sctp.port==36421,e2ap' -T json"
      #todo check all nodes?
      nodes = KubectlClient::Get.schedulable_nodes_list
      node = nodes.first

      resp = ClusterTools.exec_by_node("tshark --version", node)
      Log.info { "tshark must be version 4.0.3 or higher" }
      Log.info { "tshark output #{resp[:output]}" }

      capture = K8sTshark::TsharkPacketCapture.new
      capture.begin_capture_by_node(node, command)
    else
      capture = nil
    end
  
    capture
  end

  def self.e2_session_established?(capture : K8sTshark::TsharkPacketCapture | Nil)
    Log.info { "e2_session_established" }
    e2_found : Bool = false
    
    if !capture.nil?
      if capture.regex_match?(/e2ap\.successfulOutcome_element[^$]*e2ap.ric_ID/) 
        Log.info { "regex found " }
        e2_found = true
      else
        Log.info { "regex not found " }
      end

      Log.info { "found e2ap.successfulOutcome_element followed by e2ap.ric_ID?: #{e2_found}" }

      capture.terminate_capture
    end

    e2_found
  end
end
