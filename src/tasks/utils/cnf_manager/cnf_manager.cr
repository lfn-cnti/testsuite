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
require "../oran_monitor.cr"
require "../cnf_installation/install_common.cr"
require "../cnf_installation/manifest.cr"
require "log"
require "ecr"
require "../utils.cr"

module CNFManager
  Log = ::Log.for("CNFManager")

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
    &block : (NamedTuple(kind: String, name: String, namespace: String),
      JSON::Any, JSON::Any, Bool) -> Bool?
  ) : Bool
    logger = Log.for("workload_resource_test")
    logger.info { "Start resources test" }

    test_passed = true

    resources = [] of NamedTuple(kind: String, name: String, namespace: String)
    resource_refs(args, config, WORKLOAD_RESOURCE_KIND_NAMES) do |ref|
      resources << ref
    end

    resources.each do |resource|
      logger.info { "Testing #{resource[:kind]}/#{resource[:name]}" }
      logger.trace { resource.inspect }

      volumes = KubectlClient::Get.resource_volumes(resource[:kind], resource[:name], resource[:namespace])
      containers = KubectlClient::Get.resource_containers(resource[:kind], resource[:name], resource[:namespace])

      # yields containers individually or all at once
      targets = check_containers ? containers.as_a : [containers]
      targets.each do |target|
        resp = yield resource, target, volumes, true
        test_passed = false if resp == false
      end
    end

    initialized = resources.size > 0
    logger.info { "Workload resource test intialized: #{initialized}, test passed: #{test_passed}" }
    initialized && test_passed
  end

  def self.cnf_config_list(raise_exc : Bool = false)
    logger = Log.for("cnf_config_list")
    logger.debug { "Retrieve CNF config file" }

    cnf_testsuite = find_files("#{CNF_DIR}/*", "\"#{CONFIG_FILE}\"")
    if cnf_testsuite.empty? && raise_exc
      logger.error { "CNF config file not found" }
      raise "No cnf_testsuite.yml found! Did you run the \"cnf_install\" task?"
    else
      logger.info { "Found CNF config file: #{cnf_testsuite}" }
    end

    cnf_testsuite
  end

  def self.cnf_installed?
    !cnf_config_list(false).empty?
  end

  # (rafal-lal) TODO: why are we not accepting *.yaml
  def self.path_has_yml?(config_path)
    config_path =~ /\.yml/
  end

  # (kosstennbl) TODO: Redesign this method using new installation.
  def self.cnf_to_new_cluster(config, kubeconfig)
  end

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

    resource_keys
  end

  def self.resources_includes?(resource_keys, kind, name, namespace) : Bool
    resource_key = "#{namespace},#{kind}/#{name}".downcase
    resource_keys.includes?(resource_key)
  end
end
