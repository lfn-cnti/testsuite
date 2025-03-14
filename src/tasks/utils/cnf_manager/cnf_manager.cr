# coding: utf-8
require "totem"
require "colorize"
require "helm"
require "git"
require "uuid"
require "./points.cr"
require "./task.cr"
require "./jaeger.cr"
require "tar"
require "./oran_monitor.cr"
require "./cnf_installation/install_common.cr"
require "./cnf_installation/manifest.cr"
require "log"
require "ecr"

module CNFManager
  def self.cnf_resource_ymls(args, config)
    Log.info { "cnf_resource_ymls" }
    manifest_ymls = CNFInstall::Manifest.manifest_path_to_ymls(COMMON_MANIFEST_FILE_PATH)

    manifest_ymls = manifest_ymls.reject! { |x|
      # reject resources that contain the 'helm.sh/hook: test' annotation
      x.dig?("metadata", "annotations", "helm.sh/hook")
    }
    Log.debug { "cnf_resource_ymls: #{manifest_ymls}" }
    manifest_ymls
  end

  def self.cnf_resources(args, config, &block)
    manifest_ymls = cnf_resource_ymls(args, config)
    resource_resp = manifest_ymls.map do |resource|
      resp = yield resource
      Log.debug { "cnf_workload_resource yield resp: #{resp}" }
      resp
    end
    resource_resp
  end

  # TODO define cnf_resources
  # add all code from cnf_workload resources and the reject from the helm.workload_resource_by_kind
  # (removes helm test annotations)
  # return all the resources
  # make cnf_workload_resources call cnf_resoures with a block that calls the extra filter (all_workload_resources)

  # Applies a block to each cnf resource
  #
  # ```
  # CNFManager.cnf_workload_resources(args, config) {|cnf_config, resource| #your code}
  # ```

  def self.cnf_workload_resources(args, config, &block)
    manifest_ymls = cnf_resource_ymls(args, config)
    # call cnf cnf_resources to get unfiltered yml
    resource_ymls = Helm.all_workload_resources(manifest_ymls, default_namespace: CLUSTER_DEFAULT_NAMESPACE)
    resource_resp = resource_ymls.map do |resource|
      resp = yield resource
      Log.debug { "cnf_workload_resource yield resp: #{resp}" }
      resp
    end

    resource_resp
  end

  # test_passes_completely = workload_resource_test do | cnf_config, resource, container, initialized |
  def self.workload_resource_test(args, config,
                                  check_containers = true,
                                  check_service = false,
                                  &block : (NamedTuple(kind: String, name: String, namespace: String), JSON::Any, JSON::Any, Bool | Nil) -> Bool | Nil)
    # resp = yield resource, container, volumes, initialized
    test_passed = true
    resource_ymls = cnf_workload_resources(args, config) do |resource|
      resource
    end
    resource_names = Helm.workload_resource_kind_names(resource_ymls, default_namespace: CLUSTER_DEFAULT_NAMESPACE)
    Log.info { "resource names: #{resource_names}" }
    if resource_names && resource_names.size > 0
      initialized = true
    else
      Log.error { "no resource names found" }
      initialized = false
    end
    # todo check to see if following 'resource' variable is conflicting with above resource variable
    resource_names.each do |resource|
      Log.trace { resource.inspect }
      volumes = KubectlClient::Get.resource_volumes(kind: resource[:kind], resource_name: resource[:name], namespace: resource[:namespace])
      Log.trace { "check_service: #{check_service}" }
      Log.trace { "check_containers: #{check_containers}" }
      case resource[:kind].downcase
      when "service"
        if check_service
          Log.info { "checking service: #{resource}" }
          resp = yield resource, JSON.parse(%([{}])), volumes, initialized
          Log.debug { "yield resp: #{resp}" }
          # if any response is false, the test fails
          test_passed = false if resp == false
        end
      else
        containers = KubectlClient::Get.resource_containers(resource[:kind], resource[:name], resource[:namespace])
        if check_containers
          containers.as_a.each do |container|
            resp = yield resource, container, volumes, initialized
            Log.debug { "yield resp: #{resp}" }
            # if any response is false, the test fails
            test_passed = false if resp == false
          end
        else
          resp = yield resource, containers, volumes, initialized
          Log.debug { "yield resp: #{resp}" }
          # if any response is false, the test fails
          test_passed = false if resp == false
        end
      end
    end
    Log.debug { "workload resource test intialized: #{initialized} test_passed: #{test_passed}" }
    initialized && test_passed
  end

  def self.cnf_config_list(silent = false)
    Log.info { "cnf_config_list" }
    find_cmd = "find #{CNF_DIR}/* -name \"#{CONFIG_FILE}\""
    Log.info { "find: #{find_cmd}" }
    Process.run(
      find_cmd,
      shell: true,
      output: find_stdout = IO::Memory.new,
      error: find_stderr = IO::Memory.new
    )

    cnf_testsuite = find_stdout.to_s.split("\n").select { |x| x.empty? == false }
    Log.info { "find response: #{cnf_testsuite}" }
    if cnf_testsuite.size == 0 && !silent
      raise "No cnf_testsuite.yml found! Did you run the \"cnf_install\" task?"
    end
    cnf_testsuite
  end

  def self.cnf_installed?
    cnf_configs = self.cnf_config_list(silent: true)

    if cnf_configs.size == 0
      false
    else
      true
    end
  end

  def self.destination_cnfs_exist?
    cnf_config_list(silent: true).size > 0
  end

  def self.path_has_yml?(config_path)
    if config_path =~ /\.yml/
      true
    else
      false
    end
  end

  # if passed a directory, adds cnf-testsuite.yml to the string
  def self.ensure_cnf_testsuite_yml_path(path : String)
    Log.info { "ensure_cnf_testsuite_yml_path" }
    if path_has_yml?(path)
      yml = path
    else
      yml = path + "/cnf-testsuite.yml"
    end
  end

  def self.ensure_cnf_testsuite_dir(path : String)
    Log.info { "ensure_cnf_testsuite_yml_dir" }
    if path_has_yml?(path)
      dir = File.dirname(path)
    else
      dir = path
    end
    dir + "/"
  end

  def self.sandbox_helm_directory(cnf_testsuite_helm_directory)
    cnf_testsuite_helm_directory.split("/")[-1]
  end

  def self.cnf_to_new_cluster(config, kubeconfig)
    # (kosstennbl) TODO: Redesign this method using new installation.
  end

  def self.ensure_namespace_exists!(name, kubeconfig : String | Nil = nil)
    if kubeconfig
      with_kubeconfig(kubeconfig) { KubectlClient::Apply.namespace(name) }
    else
      KubectlClient::Apply.namespace(name)
    end

    Log.for("ensure_namespace_exists").info { "Created kubernetes namespace #{name} for the CNF install" }
    cmd = "kubectl label namespace #{name} pod-security.kubernetes.io/enforce=privileged"
    ShellCmd.run(cmd, "Label.namespace")
  rescue e : KubectlClient::ShellCMD::AlreadyExistsError
    Log.for("ensure_namespace_exists").info { "Kubernetes namespace #{name} already exists for the CNF install" }
    cmd = "kubectl label --overwrite namespace #{name} pod-security.kubernetes.io/enforce=privileged"
    ShellCmd.run(cmd, "Label.namespace")
  end

  def self.workload_resource_keys(args, config)
    resource_keys = CNFManager.cnf_workload_resources(args, config) do |resource|
      namespace = resource.dig?("metadata", "namespace") || CLUSTER_DEFAULT_NAMESPACE
      kind = resource.dig?("kind")
      name = resource.dig?("metadata", "name")
      "#{namespace},#{kind}/#{name}".downcase
    end
    resource_keys
  end

  def self.resources_includes?(resource_keys, kind, name, namespace)
    resource_key = "#{namespace},#{kind}/#{name}".downcase
    resource_keys.includes?(resource_key)
  end

  def self.find_tgz_files(helm_chart)
    Dir.glob(get_helm_tgz_glob(helm_chart))
  end

  def self.get_and_verify_tgz_name(helm_chart)
    tgz_files = find_tgz_files(helm_chart)

    if tgz_files.empty?
      Log.error { "No .tgz files found for #{get_helm_tgz_glob(helm_chart)}" }
      raise TarFileNotFoundError.new(Helm.chart_name(helm_chart))
    elsif tgz_files.size > 1
      Log.warn { "Multiple .tgz files found: #{tgz_files.join(", ")}" }
    end

    tgz_files.first
  end

  def self.get_helm_tgz_glob(helm_chart)
    "#{Helm.chart_name(helm_chart)}-*.tgz"
  end

  class TarFileNotFoundError < Exception
    def initialize(chart_name)
      super("No .tgz files found for chart #{chart_name}-*.tgz")
    end
  end
end
