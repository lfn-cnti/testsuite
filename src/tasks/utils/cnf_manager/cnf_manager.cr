# coding: utf-8
require "totem"
require "colorize"
require "../../../modules/helm"
require "../../../modules/git"
require "uuid"
require "./points.cr"
require "./task.cr"
require "../jaeger.cr"
require "../../../modules/tar"
require "../cnf_installation/install_common.cr"
require "../cnf_installation/manifest.cr"
require "log"
require "ecr"
require "../utils.cr"

module CNFManager
  Log = ::Log.for("CNFManager")

  # Raised by a test that examines the CNF's workloads when the composite
  # manifest has none to examine. The task runner turns it into one
  # not-applicable verdict with this reason, instead of the test failing on
  # its own subject (#2603).
  class NoWorkloadResources < Exception
    def initialize
      super("no workload resources in the CNF manifest (no #{KubectlClient::WORKLOAD_RESOURCES.values.select { |k| WORKLOAD_RESOURCE_KIND_NAMES.includes?(k.downcase) }.join(", ")})")
    end
  end

  # True when the composite manifest holds at least one workload resource.
  def self.workload_resources?(manifest_path : String = COMMON_MANIFEST_FILE_PATH) : Bool
    ymls = CNFInstall::Manifest.manifest_path_to_ymls(manifest_path)
    ymls.any? { |r| WORKLOAD_RESOURCE_KIND_NAMES.includes?(r.dig?("kind").to_s.downcase) }
  end

  def self.cnf_resource_ymls(args, config)
    logger = Log.for("cnf_resource_ymls")
    logger.debug { "Load YAMLs from manifest: #{COMMON_MANIFEST_FILE_PATH}" }
    manifest_ymls = CNFInstall::Manifest.manifest_path_to_ymls(COMMON_MANIFEST_FILE_PATH)

    manifest_ymls = manifest_ymls.reject! do |x|
      # reject resources that contain the 'helm.sh/hook: test' annotation
      x.dig?("metadata", "annotations", "helm.sh/hook")
    end
    logger.trace { "cnf_resource_ymls: #{manifest_ymls}" }

    manifest_ymls
  end

  def self.cnf_resources(args, config, &block)
    logger = Log.for("cnf_resources")
    logger.debug { "Map block to CNF resources" }

    manifest_ymls = cnf_resource_ymls(args, config)
    resource_resp = manifest_ymls.map do |resource|
      resp = yield resource
      resp
    end

    resource_resp
  end

  def self.cnf_workload_resources(args, config, &block)
    logger = Log.for("cnf_workload_resources")
    logger.debug { "Map block to CNF workload resources" }

    manifest_ymls = cnf_resource_ymls(args, config)
    resource_ymls = Helm.all_workload_resources(manifest_ymls, default_namespace: CLUSTER_DEFAULT_NAMESPACE)
    resource_resp = resource_ymls.map do |resource|
      resp = yield resource
      resp
    end

    resource_resp
  end

  def self.resource_refs(args, config, resource_kinds, &block : NamedTuple(kind: String, name: String, namespace: String) -> )
    logger = Log.for("resource_refs")
    logger.info { "Yielding resources: #{resource_kinds}" }
    kinds_filter = resource_kinds.map(&.downcase)

    cnf_resources(args, config) do |resource|
      kind = resource.dig("kind").as_s
      next unless kinds_filter.empty? || kinds_filter.includes?(kind.downcase)

      ref = {
        kind:      kind,
        name:      resource["metadata"]["name"].as_s,
        namespace: (resource.dig?("metadata", "namespace") || CLUSTER_DEFAULT_NAMESPACE).to_s,
      }

      yield ref
    end
  end

  def self.workload_resource_test(
    args, config, check_containers = true,
    &block : (NamedTuple(kind: String, name: String, namespace: String), JSON::Any, JSON::Any) -> Bool
  ) : Bool
    logger = Log.for("workload_resource_test")
    logger.info { "Starting test" }

    test_passed = true

    resources = [] of NamedTuple(kind: String, name: String, namespace: String)
    resource_refs(args, config, WORKLOAD_RESOURCE_KIND_NAMES) do |ref|
      resources << ref
    end
    raise NoWorkloadResources.new if resources.empty?

    resources.each do |resource|
      logger.debug { "Testing #{resource[:kind]}/#{resource[:name]}" }
      logger.trace { resource.inspect }

      volumes = KubectlClient::Get.resource_volumes(resource[:kind], resource[:name], resource[:namespace])
      containers = KubectlClient::Get.resource_containers(resource[:kind], resource[:name], resource[:namespace])

      # yields containers individually or all at once
      targets = check_containers ? containers.as_a : [containers]
      targets.each do |target|
        resp = yield resource, target, volumes
        test_passed &&= resp
      end
    end

    logger.info { "Workload resource test over #{resources.size} resource(s), test passed: #{test_passed}" }
    test_passed
  end

  def self.cnf_config_list(raise_exc : Bool = false)
    logger = Log.for("cnf_config_list")
    logger.debug { "Retrieve CNF config file" }

    cnti_testsuite = find_files("#{CNF_DIR}/*", "\"#{CONFIG_FILE}\"")
    if cnti_testsuite.empty? && raise_exc
      logger.error { "CNF config file not found" }
      raise "No cnti-testsuite.yaml found! Did you run the \"cnf_install\" task?"
    else
      logger.info { "Found CNF config file: #{cnti_testsuite}" }
    end

    cnti_testsuite
  end

  def self.cnf_installed?
    !cnf_config_list(false).empty?
  end

  def self.path_has_yml?(config_path)
    config_path =~ /\.ya?ml$/
  end

  # (kosstennbl) TODO: Redesign this method using new installation.
  def self.ensure_namespace_exists!(namespace : String) : Bool
    logger = Log.for("ensure_namespace_exists!")
    logger.info { "Ensure that namespace: #{namespace} exists on the cluster for the CNF install" }

    KubectlClient::Apply.namespace(namespace)

    KubectlClient::Utils.label("namespace", namespace, ["pod-security.kubernetes.io/enforce=privileged"])
    true
  end

  def self.workload_resource_keys(args, config) : Array(String)
    resource_keys = CNFManager.cnf_workload_resources(args, config) do |resource|
      namespace = resource.dig?("metadata", "namespace") || CLUSTER_DEFAULT_NAMESPACE
      kind = resource.dig?("kind")
      name = resource.dig?("metadata", "name")
      "#{namespace},#{kind}/#{name}".downcase
    end
    # The scanner-backed tests filter a cluster-wide report down to these
    # keys; with none there is nothing to judge, not a clean report.
    raise NoWorkloadResources.new if resource_keys.empty?

    resource_keys
  end

  def self.resources_includes?(resource_keys, kind, name, namespace) : Bool
    resource_key = "#{namespace},#{kind}/#{name}".downcase
    resource_keys.includes?(resource_key)
  end
end
