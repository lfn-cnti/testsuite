module FluentManager
  abstract class FluentBase
    getter flavor_name : String
    getter repo_url : String
    getter values_file : String
    getter values_macro : String
    getter image_name : String
    getter chart : String

    def initialize(flavor_name : String, repo_url : String, values_file : String, values_macro : String, image_name : String, chart : String)
      @flavor_name = flavor_name
      @repo_url = repo_url
      @values_file = values_file
      @values_macro = values_macro
      @image_name = image_name
      @chart = chart
    end

    def install
      Log.info { "Installing #{flavor_name} daemonset using #{values_file}" }
      Helm.helm_repo_add(flavor_name, repo_url)
      File.write(values_file, values_macro)
      begin
        Helm.install(flavor_name, chart, namespace: TESTSUITE_NAMESPACE, values: "--values #{values_file}")
        KubectlClient::Wait.resource_wait_for_install("Daemonset", flavor_name, namespace: TESTSUITE_NAMESPACE)
      rescue Helm::ShellCMD::CannotReuseReleaseNameError
        Log.info { "Release #{flavor_name} already installed" }
      end
    end

    def uninstall
      Log.info { "Uninstalling #{flavor_name} in #{TESTSUITE_NAMESPACE}" }
      Helm.uninstall(flavor_name, TESTSUITE_NAMESPACE)
    end

    def installed?
      KubectlClient::Wait.resource_wait_for_install("Daemonset", flavor_name, namespace: TESTSUITE_NAMESPACE)
    end
  end

  class FluentD < FluentBase
    def initialize
      super("fluentd", 
            "https://fluent.github.io/helm-charts", 
            "fluentd-values.yml",
            FLUENTD_VALUES,
            "fluent/fluentd-kubernetes-daemonset",
            "fluent/fluentd")
    end
  end

  class FluentDBitnami < FluentBase
    def initialize
      super("fluentdbitnami",
            "https://charts.bitnami.com/bitnami",
            "fluentd-bitnami-values.yml",
            FLUENTD_BITNAMI_VALUES,
            "bitnamilegacy/fluentd",
            "bitnami/fluentd")
    end
  end

  class FluentBit < FluentBase
    def initialize
      super("fluent-bit", 
            "https://fluent.github.io/helm-charts",
            "fluentbit-values.yml",
            FLUENTBIT_VALUES,
            "fluent/fluent-bit",
            "fluent-bit/fluent-bit")
    end
  end

  def self.find_active_match_pods : Array(JSON::Any)?
    all_flavors.each do |flavor|
      # Look for images of all flavors stored on node.
      matching_image = ClusterTools.local_match_by_image_name_with_retries(flavor.image_name)
      # When image name found on any of the nodes, check if any
      # pod with this image is currently running on the cluster.
      matching_pods = KubectlClient::Get.pods_by_digest(matching_image[:digest]) if matching_image[:found]

      return matching_pods if !matching_pods.nil? && matching_pods.first?
    end
    nil
  end

  def self.pod_tailed?(pod_name : String, fluent_pods : Array(JSON::Any)?) : Bool
    return false unless fluent_pods

    fluent_pods.each do |fluent_pod|
      fluent_pod_name = fluent_pod.dig("metadata", "name").as_s
      logs = KubectlClient::Utils.logs(fluent_pod_name, namespace: TESTSUITE_NAMESPACE)
      Log.info { "Searching logs of #{fluent_pod_name} for string #{pod_name}" }
      Log.debug { "Fluent logs: #{logs}" }
      return true if logs[:output].to_s.includes?(pod_name)
    end

    false
  end

  def self.all_flavors : Array(FluentBase)
    [FluentD.new, FluentDBitnami.new, FluentBit.new]
  end

end
