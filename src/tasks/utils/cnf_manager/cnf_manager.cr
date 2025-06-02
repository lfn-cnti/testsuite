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

  # test_passes_completely = workload_resource_test do | cnf_config, resource, container, initialized |
  def self.workload_resource_test(args, config,
                                  check_containers = true,
                                  check_service = false,
                                  &block : (NamedTuple(kind: String, name: String, namespace: String),
                                    JSON::Any, JSON::Any, Bool?) -> Bool?
  )
    logger = Log.for("workload_resource_test")
    logger.info { "Start resources test" }

    test_passed = true
    resource_ymls = cnf_workload_resources(args, config) { |resource| resource }
    resource_names = Helm.workload_resource_kind_names(resource_ymls, default_namespace: CLUSTER_DEFAULT_NAMESPACE)
    if resource_names.size > 0
      logger.info { "Found #{resource_names.size} resources to test: #{resource_names}" }
      initialized = true
    else
      logger.error { "No resources found" }
      initialized = false
    end

    resource_names.each do |resource|
      logger.trace { resource.inspect }
      logger.info { "Testing #{resource[:kind]}/#{resource[:name]}" }

      case resource[:kind].downcase
      when "service"
        if check_service
          resp = yield resource, JSON.parse(%([{}])), JSON.parse(%([{}])), initialized
          # if any response is false, the test fails
          test_passed = false if resp == false
        end
      else
        volumes = KubectlClient::Get.resource_volumes(resource[:kind], resource[:name], resource[:namespace])
        containers = KubectlClient::Get.resource_containers(resource[:kind], resource[:name], resource[:namespace])

        if check_containers
          containers.as_a.each do |container|
            resp = yield resource, container, volumes, initialized
            logger.debug { "Container #{container.dig?("metadata", "name")} result: #{resp}" }
            # if any response is false, the test fails
            test_passed = false if resp == false
          end
        else
          resp = yield resource, containers, volumes, initialized
          # if any response is false, the test fails
          test_passed = false if resp == false
        end
      end
    end
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

    begin
      KubectlClient::Apply.namespace(namespace)
    rescue e : KubectlClient::ShellCMD::AlreadyExistsError
      logger.info { "Namespace: #{namespace} already exists" }
    end

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
