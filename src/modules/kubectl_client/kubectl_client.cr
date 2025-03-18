require "totem"
require "colorize"
require "docker_client"
require "./src/modules/*"
require "./src/utils/utils.cr"
require "./src/utils/system_information.cr"

module KubectlClient
  Log = ::Log.for("KubectlClient")

  alias CMDResult = NamedTuple(status: Process::Status, output: String, error: String)
  alias BackgroundCMDResult = NamedTuple(process: Process, output: String, error: String)

  WORKLOAD_RESOURCES = {deployment:      "Deployment",
                        service:         "Service",
                        pod:             "Pod",
                        replicaset:      "ReplicaSet",
                        statefulset:     "StatefulSet",
                        daemonset:       "DaemonSet",
                        service_account: "ServiceAccount"}

  module ShellCMD
    # logger should have method name (any other scopes, if necessary) that is calling attached using .for() method.
    def self.run(cmd, logger : ::Log = Log) : CMDResult
      logger = logger.for("cmd")
      logger.trace { "command: #{cmd}" }
      status = Process.run(
        cmd,
        shell: true,
        output: output = IO::Memory.new,
        error: stderr = IO::Memory.new
      )
      logger.trace { "output: #{output}" }

      # Don't have to output log line if stderr is empty
      if stderr.to_s.size > 1
        logger.warn { "stderr: #{stderr}" }
      end

      {status: status, output: output.to_s, error: stderr.to_s}
    end

    def self.new(cmd, logger : ::Log = Log) : BackgroundCMDResult
      logger = logger.for("cmd-background")
      logger.trace { "command: #{cmd}" }
      process = Process.new(
        cmd,
        shell: true,
        output: output = IO::Memory.new,
        error: stderr = IO::Memory.new
      )
      logger.trace { "output: #{output}" }

      # Don't have to output log line if stderr is empty
      if stderr.to_s.size > 1
        logger.warn { "stderr: #{stderr}" }
      end

      {process: process, output: output.to_s, error: stderr.to_s}
    end

    def self.raise_exc_on_error(&)
      result = yield
      unless result[:status].success?
        # Add new cases to this switch if needed
        case
        when /#{ALREADY_EXISTS_ERR_MATCH}/.match(result[:error])
          raise AlreadyExistsError.new(result[:error], result[:status].exit_code)
        when /#{NOT_FOUND_ERR_MATCH}/.match(result[:error])
          raise NotFoundError.new(result[:error], result[:status].exit_code)
        when /#{NETWORK_ERR_MATCH}/i.match(result[:error])
          raise NetworkError.new(result[:error], result[:status].exit_code)
        else
          raise UnspecifiedError.new(result[:error], result[:status].exit_code)
        end
      end
      result
    end

    class K8sClientCMDException < Exception
      MSG_TEMPLATE = "kubectl CMD failed, exit code: %s, error: %s"

      def initialize(message : String?, exit_code : Int32, cause : Exception? = nil)
        super(MSG_TEMPLATE % {exit_code, message}, cause)
      end
    end

    class AlreadyExistsError < K8sClientCMDException
    end

    class NotFoundError < K8sClientCMDException
    end

    class NetworkError < K8sClientCMDException
    end

    class UnspecifiedError < K8sClientCMDException
    end
  end

  def self.installation_found?(verbose = false, offline_mode = false) : Bool
    kubectl_installation(verbose = false, offline_mode = false).includes?("kubectl found")
  end

  def self.server_version : String
    logger = Log.for("server_version")

    result = ShellCMD.run("kubectl version --output json", logger)
    version = JSON.parse(result[:output])["serverVersion"]["gitVersion"].as_s
    version = version.gsub("v", "")

    logger.info { "K8s server version is: #{version}" }
    version
  end

  def self.names_from_json_array_to_s(resource : Array(JSON::Any)) : String
    resource.map { |item| item.dig?("metadata", "name") }.join(", ")
  end
end