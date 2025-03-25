# (rafal-lal) TODO: add spec for it
module KindManager
  KIND_BIN       = "#{tools_path()}/kind/kind"
  KUBECONFIG_TPL = "#{tools_path()}/kind/%s_admin.conf"

  Log = ::Log.for("KindManager")

  def self.create_cluster(name : String, kind_config : String?, k8s_version : String?) : KindManager::Cluster?
    logger = Log.for("create_cluster")
    logger.info { "Creating Kind Cluster '#{name}'" }

    kubeconfig = KUBECONFIG_TPL % {name}
    kind_config_opt = "--config #{kind_config}" unless kind_config.nil?
    unless File.exists?("#{kubeconfig}")
      # Debug notes:
      # * Add --verbosity 100 to debug kind issues.
      # * Use --retain to retain cluster in case there is an error with creation.
      cmd = "#{KIND_BIN} create cluster --name #{name} #{kind_config_opt} --image kindest/node:v#{k8s_version} " +
            "--kubeconfig #{kubeconfig}"
      unless ShellCmd.run(cmd, "KindManager#create_cluster")[:status].success?
        logger.error { "Error while creating Kind Cluster" }
        return nil
      end

      logger.info { "Kind Cluster '#{name}' created" }
    else
      logger.warn { "File '#{kubeconfig}' already exists, Kind Cluster not created" }
      return nil
    end

    return KindManager::Cluster.new(name, kubeconfig)
  end

  def self.delete_cluster(name : String) : Bool
    logger = Log.for("delete_cluster")
    logger.info { "Deleting Kind Cluster: #{name}" }
    
    unless ShellCmd.run("#{KIND_BIN} delete cluster --name #{name}", "KindManager#delete_cluster")[:status].success?
      logger.error { "Error while deleting Kind Cluster" }
      return false
    end

    kubeconfig = KUBECONFIG_TPL % {name}
    if File.exists?(kubeconfig)
      logger.debug { "Deleting kubeconfig: '#{kubeconfig}' for Kind Cluster: #{name}" }
      File.delete?(kubeconfig)
    end

    true
  end

  def self.disable_cni_config : String
    kind_config = "#{tools_path}/kind/disable_cni.yml"
    unless File.exists?(kind_config)
      File.write(kind_config, DISABLE_CNI)
    end

    kind_config
  end

  struct Cluster
    property name
    property kubeconfig
    # (rafal-lal) TODO: idea for moving CNF to new KIND cluster, discussion needed.
    # property cnf_installed : Bool
    @logger : ::Log

    def initialize(@name : String, @kubeconfig : String)
      @logger = Log.for("cluster-#{@name}")
    end

    def cluster_ready? : Bool
      @logger.info { "Waiting for cluster to be ready" }
      @logger.debug { "Timed out while waiting for nodes to be ready" } unless nodes_ready?
      @logger.debug { "Timed out while waiting for pods to be ready" } unless pods_ready?
      @logger.info { "Ready: '#{nodes_ready? && pods_ready?}'" }
      nodes_ready? && pods_ready?
    end

    private def nodes_ready? : Bool
      nodes = with_kubeconfig(@kubeconfig) do
        KubectlClient::Get.resource("nodes").dig("items").as_a.map { |node| node.dig("metadata", "name").as_s }
      end
      ready = with_kubeconfig(@kubeconfig) do
        nodes.all? do |node_name|
          KubectlClient::Wait.wait_for_condition("node", node_name, "condition=Ready", wait_count = 300)
        end
      end
    end

    private def pods_ready?
      pods = with_kubeconfig(@kubeconfig) do
        KubectlClient::Get.resource("pods", all_namespaces: true).dig("items").as_a
      end
      ready = with_kubeconfig(@kubeconfig) do
        pods.all? do |pod|
          pod_name = pod.dig("metadata", "name").as_s
          pod_ns = pod.dig("metadata", "namespace").as_s
          KubectlClient::Wait.resource_wait_for_install("pod", pod_name, 300, pod_ns)
        end
      end
    end
  end
end
