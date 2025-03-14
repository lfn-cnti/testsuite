require "totem"
require "colorize"
require "./cnf_manager/cnf_manager.cr"
require "halite"


module K8sTshark
  class TsharkPacketCapture
    property capture_file_path : String
    property pid : Int32?
    private property node_match : JSON::Any?

    def initialize
      @capture_file_path = ""
    end

    def finalize
      if @pid
        terminate_capture
      end
    end

    # Method to provide a block context for capture by label.
    def self.begin_capture_by_label(label_key : String, label_value : String, command : String = "", &block : TsharkPacketCapture ->)
      capture = new
      begin
        capture.begin_capture_by_label(label_key, label_value, command)
        yield capture
      ensure
        capture.terminate_capture
      end
    end
    
    # Method to provide a block context for capture by node.
    def self.begin_capture_by_node(node : JSON::Any, command : String = "", &block : TsharkPacketCapture ->)
      capture = new
      begin
        capture.begin_capture_by_node(node, command)
        yield capture
      ensure
        capture.terminate_capture
      end
    end

    # Starts a tshark packet capture on the node where the pod with the specified label is running.
    # label_key and label_value: Used to identify the pod's label.
    # command: Parameters to be passed to tshark.
    def begin_capture_by_label(label_key : String, label_value : String, command : String = "")
      Log.info { "Searching for the pod matching the label '#{label_key}:#{label_value}'."}
      all_pods = KubectlClient::Get.pods_by_nodes(KubectlClient::Get.schedulable_nodes_list)
      pod_match = KubectlClient::Get.pods_by_labels(all_pods, {label_key =>label_value}).first?
  
      unless pod_match && pod_match.dig?("metadata", "name")
        error_message = "Pod with label '#{label_key}:#{label_value}' could not be found."
        Log.error { error_message }
        raise K8sTsharkError.new(error_message)
      end

      pod_name = pod_match.dig("metadata", "name")
      Log.info { "Pod '#{pod_name}'' matches the label '#{label_key}:#{label_value}'." }

      Log.info { "Searching for the node running the pod '#{pod_name}'." }
      @node_match = KubectlClient::Get.nodes_by_pod(pod_match).first
  
      unless @node_match && @node_match.not_nil!.dig?("metadata", "name")
        error_message = "Node for pod '#{pod_name}' could not be found."
        Log.error { error_message }
        raise K8sTsharkError.new(error_message)
      end

      node_name = node_match.not_nil!.dig("metadata", "name")
      Log.info { "Pod '#{pod_name}' is running on node '#{node_name}'." }
  
      begin_capture_common(command)
    end
  
    # Starts a tshark packet capture on the specified node.
    # node: The node where the capture should be performed.
    # command: Parameters to be passed to tshark.
    # duration: Optional; specifies the capture duration, eliminating the need to call terminate_capture manually.
    def begin_capture_by_node(node : JSON::Any, command : String = "")
      @node_match = node
      begin_capture_common(command)
    end

    # Common method to unify capture by label and node.
    private def begin_capture_common(command : String)
      if @pid
        Log.warn { "Ongoing capture process exists, terminate it or create a new capture." }
        return
      end
    
      Log.info { "Starting tshark capture with command: #{command}." }
    
      @capture_file_path = generate_capture_file_path()
      Log.info { "Capturing packets on path: #{@capture_file_path}." }
    
      # Other possible options to resolve the pid conundrum:
      # 1. pgrep tshark -f -x "tshark #{command}"
      # 2. ...; echo $! > /tmp/pidfile
      # 3. bake in 'echo $$!', retrieve from some file
      # 4. fix kubectl_client to return the pid of the process that is launched, not the shell
      pid_file = "/tmp/pidfile"
      pid_command = "ps -eo pid,cmd,start --sort=start_time | grep '[t]shark' | tail -1 | awk '{print $1}'  > #{pid_file}"
      capture_command = "tshark #{command} > #{@capture_file_path} 2>&1"
    
      launch_capture(capture_command)
      retrieve_pid(pid_command, pid_file)
    end

    # Terminates the tshark packet capture process.
    def terminate_capture
      if @pid
        Log.info { "Terminating packet capture with PID: #{@pid}." }
        Log.info { "Capture collected on path: #{@capture_file_path}." }

        # Some tshark captures were left in zombie states if only kill/kill -9 was invoked.
        ClusterTools.exec_by_node_bg("kill -15 #{@pid}", @node_match.not_nil!)
        sleep 1
        ClusterTools.exec_by_node_bg("kill -9 #{@pid}", @node_match.not_nil!)

        @pid = nil
        @node_match = nil
      else
        Log.warn { "No active capture process to terminate." }
      end
    end

    # Searches the capture file for lines matching the specified regex pattern.
    # Returns an array of matching lines.
    def regex_search(pattern : Regex) : Array(String)
      matches = [] of String

      if @capture_file_path.empty?
        Log.warn { "Cannot find a match using a regular expression before a capture has been started." }
      else
        Log.info { "Collecting lines matching the regular expression #{pattern}." }
        file_content = File.read(@capture_file_path)
        matches = file_content.scan(pattern).map(&.string)
        Log.debug { "Printing out matching lines:\n#{matches}" }
      end

      matches
    end

    # Checks if any line in the capture file matches the specified regex pattern.
    # Returns true if a match is found, otherwise false.
    def regex_match?(pattern : Regex) : Bool
      if @capture_file_path.empty?
        Log.warn { "Cannot find a match using a regular expression before a capture has been started." }
      else
        Log.info { "Finding a match for regular expression: #{pattern} in file: #{capture_file_path}." }
        file_content = File.read(@capture_file_path)
        if file_content.scan(pattern).any?
          Log.debug { "Match found for regular expression: #{pattern}" }
          return true
        end
      end

      false
    end

    # Retrieves the file path where the capture is stored.
    def get_capture_file_path : String
      @capture_file_path
    end

    private def generate_capture_file_path : String
      name_id = Random.new.next_int.abs

      "/tmp/tshark-#{name_id}.pcap"
    end

    private def launch_capture(command : String)
      begin
        # Start tshark capture.
        ClusterTools.exec_by_node_bg(command, @node_match.not_nil!)
      rescue ex : Exception
        error_message = "Could not start tshark capture process: #{ex.message}"
        Log.error { error_message }
        raise K8sTsharkError.new(error_message)
      end
    end

    private def retrieve_pid(command : String, pid_file : String)
      begin
        # Store the pid of the tshark process.
        ClusterTools.exec_by_node_bg(command, @node_match.not_nil!)
    
        error_message = "Could not retrieve the PID of the tshark process"

        # Wait for pidfile to be readable using repeat_with_timeout
        pid_found = repeat_with_timeout(timeout: 10, errormsg: error_message) do
          File.exists?(pid_file) && File.size(pid_file) > 0
        end

        if pid_found
          @pid = File.read(pid_file).strip.to_i
          Log.info { "tshark process started with PID: #{@pid}" }
        else
          # Attempt to kill the capture process if it was started.
          ClusterTools.exec_by_node_bg("pkill -15 tshark && sleep 1 && pkill -9 tshark", @node_match.not_nil!)
          raise K8sTsharkError.new(error_message)
        end
      ensure
        File.delete(pid_file) if File.exists?(pid_file)
      end
    end
  end

  class K8sTsharkError < Exception
    def initialize(message : String)
      super(message)
    end
  end
end
