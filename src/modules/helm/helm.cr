require "../kubectl_client"
require "./utils/utils.cr"
require "./utils/binary_reference.cr"
require "./utils/system_information.cr"

module Helm
  Log = ::Log.for("Helm")

  BinarySingleton = BinaryReference.new
  alias CMDResult = NamedTuple(status: Process::Status, output: String, error: String)

  module ShellCMD
    # logger should have method name (any other scopes, if necessary) that is calling attached using .for() method.
    def self.run(cmd, logger : ::Log = Log, force_output = false) : CMDResult
      logger = logger.for("cmd")
      logger.debug { "command: #{cmd}" }
      status = Process.run(
        cmd,
        shell: true,
        output: output = IO::Memory.new,
        error: stderr = IO::Memory.new
      )
      if force_output == false
        logger.trace { "output: #{output}" }
      else
        logger.info { "output: #{output}" }
      end

      # Don't have to output log line if stderr is empty
      if stderr.to_s.size > 1
        logger.warn { "stderr: #{stderr}" }
      end

      {status: status, output: output.to_s, error: stderr.to_s}
    end

    def self.raise_exc_on_error(&)
      result = yield
      unless result[:status].success?
        # Add new cases to this switch if needed
        case
        when /#{RELEASE_NOT_FOUND}/.match(result[:error])
          raise ReleaseNotFound.new(result[:error], result[:status].exit_code)
        when /#{REPO_NOT_FOUND}/i.match(result[:error])
          raise RepoNotFound.new(result[:error], result[:status].exit_code)
        when /#{CANNOT_REUSE_RELEASE_NAME}/i.match(result[:error])
          raise CannotReuseReleaseNameError.new(result[:error], result[:status].exit_code)
        else
          raise HelmCMDException.new(result[:error], result[:status].exit_code)
        end
      end
      result
    end

    class HelmCMDException < Exception
      MSG_TEMPLATE = "helm CMD failed, exit code: %s, error: %s"

      def initialize(message : String?, exit_code : Int32, cause : Exception? = nil)
        super(MSG_TEMPLATE % {exit_code, message}, cause)
      end
    end

    class ReleaseNotFound < HelmCMDException
    end

    class RepoNotFound < HelmCMDException
    end

    class CannotReuseReleaseNameError < HelmCMDException
    end
  end

  def self.generate_manifest(release_name : String, namespace : String) : String
    logger = Log.for("generate_manifest")
    logger.info { "Generating manifest from installed CNF: #{release_name}" }

    helm = BinarySingleton.helm

    resp = ShellCMD.raise_exc_on_error { ShellCMD.run("#{helm} get manifest #{release_name} --namespace #{namespace}") }
    logger.info { "Manifest was generated successfully" } if resp[:status].success? && !resp[:output].empty?
    resp[:output]
  end

  def self.workload_resource_by_kind(ymls : Array(YAML::Any), kind : String) : Array(YAML::Any)
    logger = Log.for("workload_resource_by_kind")
    logger.debug { "kind: #{kind}" }
    logger.debug { "ymls: #{ymls}" }

    resources = ymls.select { |x| x["kind"]? == kind }.reject! do |x|
      # reject resources that contain the 'helm.sh/hook: test' annotation
      x.dig?("metadata", "annotations", "helm.sh/hook")
    end

    resources
  end

  def self.all_workload_resources(yml : Array(YAML::Any), default_namespace : String = "default") : Array(YAML::Any)
    resources = KubectlClient::WORKLOAD_RESOURCES.map { |_, v| Helm.workload_resource_by_kind(yml, v) }.flatten
    # This patch works around a Helm behaviour https://github.com/helm/helm/issues/10737
    #
    # The below map block inserts "metadata.namespace" key into resources that do not specify a namespace.
    # The parsed resource YAML comes from "helm template" command.
    #
    # The "helm template" command ONLY renders the helm chart with variables substituted.
    #
    # The YAML output by "helm template" command would only contain the namespace for the resources if:
    #   1. The helm chart has hardcoded namespaces.
    #   2. OR The helm chart contains a Go variable like below:
    #      namespace: {{ .Release.Namespace }}
    #
    # If none of the above are present,
    # then the "-n <namespace>" argument passed to "helm template" command is not used anywhere in the output.

    # Below is a scenario that causes an issue for cnf_setup:
    #
    # 0: CNF has helm chart that does not specify namespace for the resources in the YAML chart.
    #
    # 1. User mentions "helm_install_namespace: hello-world" in CNF config.
    #
    # 2. cnf_setup installs the Helm chart with "-n hello-world" namespace flag.
    #
    # 3. cnf_setup calls the CNFManager.workload_resource_test or cnf_workload_resources helper to fetch YAMLs
    #    The YAMLs are from the "helm template" output.
    #    And these now do not contain namespace for any resources due to [0] mentioned above.
    #
    # 4. cnf_setup calls KubectlClient::Get.resource_wait_for_install assuming the resource is in the default namespace.
    #    Since the resource does not exist, the cnf_setup loops until timeout waiting for install.
    #
    # Similarly, any test that uses the CNFManager helpers to look for resources in the CNF,
    # would also assume default namespace.
    #
    # To resolve the issue, we insert the namespace into the resource YAMLs being returned.
    resources_with_namespace = resources.map do |resource|
      ensure_resource_with_namespace(resource, default_namespace)
    end
    Log.for("all_workload_resources").debug { "#{resources_with_namespace}" }
    resources_with_namespace
  end

  def self.ensure_resource_with_namespace(resource : YAML::Any, default_namespace : String) : YAML::Any
    if resource.dig?("metadata", "namespace") != nil
      resource
    else
      # Required workaround because we cannot assign a key or mutate YAML::Any

      # Step-1: Convert resource to Hash(YAML::Any, YAML::Any)
      resource = resource.as_h

      # Step-2: Convert metadata from YAML:Any to a Hash(YAML::Any, YAML::Any)
      metadata = resource["metadata"].as_h

      # Step-3: The key in the hash is of type YAML::Any.
      # So convert the string "namespace" to YAML.
      namespace_yaml_key = YAML.parse("namespace".to_yaml)

      # Step-4: Convert default namespace to YAML and assign it to the namespace key
      metadata[namespace_yaml_key] = YAML.parse(default_namespace.to_yaml)

      # Step-5: Convert the "metadata" key name to YAML::Any
      metadata_yaml_key = YAML.parse("metadata".to_yaml)

      # Step-6: Set the metadata on the resource
      resource[metadata_yaml_key] = YAML.parse(metadata.to_yaml)
      resource = YAML.parse(resource.to_yaml)
      resource
    end
  end

  def self.workload_resource_kind_names(
    resources : Array(YAML::Any),
    default_namespace : String = "default"
  ) : Array(NamedTuple(kind: String, name: String, namespace: String))
    resource_names = resources.map do |x|
      namespace = (x.dig?("metadata", "namespace") || default_namespace).to_s
      {
        kind:      x["kind"].as_s,
        name:      x["metadata"]["name"].as_s,
        namespace: namespace,
      }
    end
    Log.for("workload_resource_kind_names").debug { "resource names: #{resource_names}" }
    resource_names
  end

  def self.kind_exists?(args, config, kind, default_namespace : String = "default") : Bool
    logger = Log.for("kind_exists?")
    logger.debug { "kind: #{kind}" }
    resource_ymls = CNFManager.cnf_workload_resources(args, config) do |resource|
      resource
    end

    default_namespace = "default"
    if !config.cnf_config[:helm_install_namespace].empty?
      default_namespace = config.cnf_config[:helm_install_namespace]
    end
    resource_names = Helm.workload_resource_kind_names(resource_ymls, default_namespace: default_namespace)
    found = false
    resource_names.each do |resource|
      if resource[:kind].downcase == kind.downcase
        found = true
      end
    end
    logger.debug { "kind found: #{found}" }
    found
  end

  def self.helm_repo_add(helm_repo_name, helm_repo_url) : Bool
    logger = Log.for("helm_repo_add")
    logger.info { "Adding helm repository: #{helm_repo_name}" }
    helm = BinarySingleton.helm

    resp = nil
    begin
      resp = ShellCMD.raise_exc_on_error { ShellCMD.run("#{helm} repo add #{helm_repo_name} #{helm_repo_url}", logger) }
    rescue ex : ShellCMD::RepoNotFound
      logger.error { "Failed to add helm repository, exception msg: #{ex.message}" }
    end

    # Helm version v3.3.3 gave us a surprise
    if resp.nil?
      false
    else
      resp[:output] =~ /has been added|already exists/ ||
        resp[:error] =~ /has been added|already exists/ ? true : false
    end
  end

  def self.helm_gives_k8s_warning? : {Bool, String?}
    logger = Log.for("helm_gives_k8s_warning?")
    helm = BinarySingleton.helm

    begin
      resp = ShellCMD.raise_exc_on_error { ShellCMD.run("#{helm} list", logger) }
      # Helm version v3.3.3 gave us a surprise
      if (resp[:output] + resp[:error]) =~ /WARNING: Kubernetes configuration file is/
        return {true, "For this version of helm you must set your K8s config file permissions to chmod 700"}
      end

      {false, nil}
    rescue
      {true, "Please use newer version of helm"}
    end
  end

  def self.chart_name(helm_chart_repo) : String
    helm_chart_repo.split("/").last
  end

  def self.template(release_name, helm_chart_or_directory,
                    output_file : String = "cnfs/temp_template.yml",
                    namespace : String? = nil,
                    values : String? = nil) : CMDResult
    logger = Log.for("template")
    helm = BinarySingleton.helm
    cmd = "#{helm} template"
    cmd = "#{cmd} -n #{namespace}" if namespace != nil
    cmd = "#{cmd} #{release_name} #{values} #{helm_chart_or_directory} > #{output_file}"

    ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
  end

  # the way values currently work is they are combined with the chart
  # (e.g. coredns --values FILENAME.yaml
  # or
  # coredns --set test.value.test=new_value --set test.value.anothertest=new_value)
  def self.install(
    release_name : String, helm_chart : String, namespace : String? = nil, create_namespace = false, values = nil
  ) : CMDResult
    logger = Log.for("install")
    logger.info { "Installing helm chart: #{helm_chart}" }
    logger.debug { "Values: #{values}" }

    helm = BinarySingleton.helm
    cmd = "#{helm} install #{release_name} #{values} #{helm_chart}"
    cmd = "#{cmd} -n #{namespace}" if namespace
    cmd = "#{cmd} --create-namespace" if create_namespace
    cmd = "#{cmd} #{values}" if values
    ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
  end

  def self.uninstall(release_name : String, namespace : String? = nil, wait : Bool = false) : CMDResult
    logger = Log.for("uninstall")
    logger.info { "Uninstalling helm chart: #{release_name}" }

    helm = BinarySingleton.helm
    cmd = "#{helm} uninstall #{release_name}"
    cmd = "#{cmd} -n #{namespace}" if namespace
    cmd = "#{cmd} --wait" if wait
  
    ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
  end

  def self.pull(helm_repo_name, helm_chart_name, version = nil, destination = nil, untar = true) : CMDResult
    logger = Log.for("pull")
    full_chart_name = "#{helm_repo_name}/#{helm_chart_name}"
    logger.info { "Pulling helm chart: #{full_chart_name}" }

    helm = BinarySingleton.helm
    cmd = "#{helm} pull #{full_chart_name}"
    cmd = "#{cmd} --version" if version
    cmd = "#{cmd} --untar" if untar
    cmd = "#{cmd} --destination #{destination}" if destination
    ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
  end

  # This method could be overloaded but there is a trap - if calling this method without all args provided,
  # to make use of default values for them, both method could be easily matched.
  def self.pull_oci(oci_address, version = nil, destination = nil, untar = true) : CMDResult
    logger = Log.for("pull")
    logger.info { "Pulling helm chart from OCI registry: #{oci_address}" }

    helm = BinarySingleton.helm
    cmd = "#{helm} pull #{oci_address}"
    cmd = "#{cmd} --version" if version
    cmd = "#{cmd} --untar" if untar
    cmd = "#{cmd} --destination #{destination}" if destination
    ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
  end

  class ManifestGenerationError < Exception
    def initialize(stderr : String)
      super("✖ ERROR: generating manifest was not successfull.\nHelm stderr --> #{stderr}")
    end
  end
end
