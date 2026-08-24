require "file_utils"

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

    # Digest pinned in image_name ("repo:tag@sha256:..."). The helm values files
    # pin the same digest, so a collector installed by the testsuite always runs
    # exactly this image. Empty when the flavor pins no digest.
    def image_digest : String
      image_name.partition("@")[2]
    end

    def install
      Log.info { "Installing #{flavor_name} daemonset using #{values_file}" }
      Helm.helm_repo_add(flavor_name, repo_url)
      FileUtils.mkdir_p(Setup::RENDERED_MANIFESTS_DIR)
      values_path = File.join(Setup::RENDERED_MANIFESTS_DIR, values_file)
      File.write(values_path, values_macro)
      begin
        Helm.install(flavor_name, chart, namespace: TESTSUITE_NAMESPACE, values: "--values #{values_path}")
        KubectlClient::Wait.resource_wait_for_install("Daemonset", flavor_name, namespace: TESTSUITE_NAMESPACE)
      rescue Helm::ShellCMD::CannotReuseReleaseNameError
        Log.info { "Release #{flavor_name} already installed" }
      end
    end

    def uninstall
      Log.info { "Uninstalling #{flavor_name} in #{TESTSUITE_NAMESPACE}" }
      Helm.uninstall(flavor_name, TESTSUITE_NAMESPACE)
    rescue Helm::ShellCMD::ReleaseNotFound
      Log.info { "#{flavor_name} release not found, nothing to uninstall" }
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
            # renovate: datasource=docker depName=fluent/fluentd-kubernetes-daemonset
            "fluent/fluentd-kubernetes-daemonset:v1.19.3-debian-elasticsearch8-1.1@sha256:88da01d42636bb6f659f4116d66cafe44f7ee2436ddbd5c3b8bd595449f2a639",
            "fluentd/fluentd")
    end
  end

  class FluentBit < FluentBase
    def initialize
      super("fluent-bit",
            "https://fluent.github.io/helm-charts",
            "fluentbit-values.yml",
            FLUENTBIT_VALUES,
            # renovate: datasource=docker depName=fluent/fluent-bit
            "fluent/fluent-bit:5.1.1@sha256:a941bdd5ca552b2c6597fc7b3bccf2e61d30873939bab5700963de0e94ac6169",
            "fluent-bit/fluent-bit")
    end
  end

  def self.find_active_match_pods : Array(JSON::Any)?
    all_flavors.each do |flavor|
      # Match running pods by the digest pinned in the flavor definition, read
      # from pod container statuses. Detection used to resolve that digest via
      # node .status.images first, which the kubelet refreshes asynchronously:
      # a freshly installed collector could stay invisible there for over 30s,
      # longer than the retry budget, making routed_logs detection flaky.
      digest = flavor.image_digest
      next if digest.empty?
      matching_pods = KubectlClient::Get.pods_by_digest(digest)

      return matching_pods if matching_pods.first?
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
    [FluentD.new, FluentBit.new]
  end

end
