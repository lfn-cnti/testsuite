require "../utils.cr"

module CNFInstall
  Log = ::Log.for("CNFInstall")

  alias ResourceInfo  = NamedTuple(kind: String, name: String, namespace: String?)
  alias DescendantMap = Hash(ResourceInfo, Array(KubectlClient::ResourceDescendant))

  def self.install_cnf(cli_args)
    parsed_args = parse_install_cli_args(cli_args)
    cnf_config_path = parsed_args[:config_path]
    if cnf_config_path.empty?
      stdout_failure "cnf-config or cnf-path parameter with valid CNF configuration should be provided."
      exit(1)
    end
    config = Config.parse_cnf_config_from_file(cnf_config_path)
    ensure_cnf_dir_structure()
    FileUtils.cp(cnf_config_path, File.join(CNF_DIR, CONFIG_FILE))

    prepare_deployment_directories(config, cnf_config_path)

    deployment_managers = create_deployment_manager_list(config)
    install_deployments(parsed_args: parsed_args, deployment_managers: deployment_managers)
  end

  def self.parse_install_cli_args(cli_args)
    logger = Log.for("parsed_cli_args")

    logger.trace { "CLI args: #{cli_args.inspect}" }
    cnf_config_path = ""
    timeout = 1800
    skip_wait_for_install = cli_args.raw.includes? "skip_wait_for_install"

    if cli_args.named.keys.includes? "cnf-config"
      cnf_config_path = cli_args.named["cnf-config"].as(String)
    elsif cli_args.named.keys.includes? "cnf-path"
      cnf_config_path = cli_args.named["cnf-path"].as(String)
    end
    cnf_config_path = self.ensure_cnf_config_path_file(cnf_config_path)

    if cli_args.named.keys.includes? "timeout"
      timeout = cli_args.named["timeout"].to_i
    end
    parsed_args = {config_path: cnf_config_path, timeout: timeout, skip_wait_for_install: skip_wait_for_install}
    logger.debug { "Parsed args: #{parsed_args}" }
    parsed_args
  end
  
  def self.parse_uninstall_cli_args(cli_args)
    logger = Log.for("parsed_uninstall_cli_args")
    logger.trace { "CLI args: #{cli_args.inspect}" }
  
    timeout = cli_args.named.keys.includes?("timeout") ? cli_args.named["timeout"].to_i : GENERIC_OPERATION_TIMEOUT
    skip_wait_for_uninstall = cli_args.raw.includes?("skip_wait_for_uninstall")
  
    parsed_args = {timeout: timeout, skip_wait_for_uninstall: skip_wait_for_uninstall}
    logger.debug { "Parsed uninstall args: #{parsed_args}" }
    parsed_args
  end

  def self.ensure_cnf_config_path_file(path)
    if CNFManager.path_has_yml?(path)
      yml = path
    elsif File.directory?(path)
      yml = File.join(path, CONFIG_FILE)
    else
      stdout_failure "Invalid CNF configuration file: #{path}."
      exit(1)
    end
  end

  def self.ensure_cnf_dir_structure
    FileUtils.mkdir_p(CNF_DIR)
    FileUtils.mkdir_p(DEPLOYMENTS_DIR)
    FileUtils.mkdir_p(CNF_TEMP_FILES_DIR)
  end

  def self.prepare_deployment_directories(config, cnf_config_path)
    # Deployment names are expected to be unique (ensured in config)
    config.deployments.helm_charts.each do |helm_chart_config|
      FileUtils.mkdir_p(File.join(DEPLOYMENTS_DIR, helm_chart_config.name))
    end
    config.deployments.helm_dirs.each do |helm_directory_config|
      source_dir = File.join(Path[cnf_config_path].dirname, helm_directory_config.helm_directory)
      destination_dir = File.join(DEPLOYMENTS_DIR, helm_directory_config.name)
      FileUtils.mkdir_p(destination_dir)
      FileUtils.cp_r(source_dir, destination_dir)
    end
    config.deployments.manifests.each do |manifest_config|
      source_dir = File.join(Path[cnf_config_path].dirname, manifest_config.manifest_directory)
      destination_dir = File.join(DEPLOYMENTS_DIR, manifest_config.name)
      FileUtils.mkdir_p(destination_dir)
      FileUtils.cp_r(source_dir, destination_dir)
    end
  end

  def self.create_deployment_manager_list(config)
    deployment_managers = [] of DeploymentManager
    config.deployments.helm_charts.each do |helm_chart_config|
      deployment_managers << HelmChartDeploymentManager.new(helm_chart_config, config.common)
    end
    config.deployments.helm_dirs.each do |helm_directory_config|
      deployment_managers << HelmDirectoryDeploymentManager.new(helm_directory_config)
    end
    config.deployments.manifests.each do |manifest_config|
      deployment_managers << ManifestDeploymentManager.new(manifest_config)
    end
    deployment_managers.sort! { |a, b| a.deployment_priority <=> b.deployment_priority }
  end

  def self.install_deployments(parsed_args, deployment_managers)
    deployment_managers.each do |deployment_manager|
      deployment_name = deployment_manager.deployment_name

      stdout_success "Installing deployment \"#{deployment_name}\"."
      result = deployment_manager.install
      if !result
        stdout_failure "Deployment of \"#{deployment_name}\" failed during CNF installation."
        exit 1
      end

      generated_deployment_manifest = deployment_manager.generate_manifest
      deployment_manifest_path = File.join(DEPLOYMENTS_DIR, deployment_name, DEPLOYMENT_MANIFEST_FILE_NAME)
      Manifest.add_manifest_to_file(deployment_name, generated_deployment_manifest, deployment_manifest_path)
      Manifest.add_manifest_to_file(deployment_name, generated_deployment_manifest, COMMON_MANIFEST_FILE_PATH)

      if !parsed_args[:skip_wait_for_install]
        wait_for_deployment_installation(deployment_name, generated_deployment_manifest, parsed_args[:timeout])
      end
    end
  end

  def self.uninstall_cnf(cli_args)
    parsed_args = parse_uninstall_cli_args(cli_args)
    cnf_config_path = File.join(CNF_DIR, CONFIG_FILE)
    if !File.exists?(cnf_config_path)
      stdout_warning "CNF uninstallation skipped. No CNF config found in #{CNF_DIR} directory. "
      return true
    end
    config = Config.parse_cnf_config_from_file(cnf_config_path)

    deployment_managers = create_deployment_manager_list(config).reverse
    result = uninstall_deployments(parsed_args, deployment_managers)

    FileUtils.rm_rf(CNF_DIR)
    result
  end

  def self.uninstall_deployments(parsed_args, deployment_managers)
    all_uninstallations_successfull = true

    deployment_managers.each do |deployment_manager|
      deployment_name = deployment_manager.deployment_name
      manifest_path = File.join(DEPLOYMENTS_DIR, deployment_name, DEPLOYMENT_MANIFEST_FILE_NAME)

      unless File.exists?(manifest_path)
        stdout_warning "Skipping uninstallation of deployment \"#{deployment_name}\": no manifest at #{manifest_path}."
        next
      end

      # discover resources
      resources = load_resources(manifest_path)

      # make a snapshot of descendant relations for each resource
      descendant_map = build_descendant_map(resources)

      uninstall_success = deployment_manager.uninstall
      all_uninstallations_successfull &&= uninstall_success

      if uninstall_success && !parsed_args[:skip_wait_for_uninstall] && !descendant_map.empty?
        all_uninstallations_successfull &&= wait_for_deployment_uninstallation(deployment_name, descendant_map, parsed_args[:timeout])
      end
    end

    if all_uninstallations_successfull
      msg = parsed_args[:skip_wait_for_uninstall] ?
        "All CNF deployments were uninstalled; resources will continue deleting in background." :
        "All CNF deployments were uninstalled."
      stdout_success msg
    else
      stdout_failure "CNF uninstallation wasn't successful; check logs for details."
    end

    all_uninstallations_successfull
  end

  private def self.load_resources(manifest_path : String) : Array(ResourceInfo)
    manifest = Manifest.combine_ymls_as_manifest_string(
      Manifest.manifest_path_to_ymls(manifest_path)
    )

    resources = Helm.workload_resource_kind_names(
      Manifest.manifest_string_to_ymls(manifest)
    )

    resources.map do |ref|
      { kind: ref[:kind], name: ref[:name], namespace: ref[:namespace].as(String?) }
    end
  end

  private def self.build_descendant_map(resources : Array(ResourceInfo)) : DescendantMap
    resources.each_with_object({} of ResourceInfo => Array(KubectlClient::ResourceDescendant)) do |res, map|
      if root_uid = KubectlClient::Get.resource_uid(res[:kind], res[:name], res[:namespace])
        map[res] = KubectlClient::Get.descendants(res[:kind], res[:name], res[:namespace])
      end
    end
  end

  def self.wait_for_deployment_installation(deployment_name, deployment_manifest, timeout)
    resources_info = Helm.workload_resource_kind_names(Manifest.manifest_string_to_ymls(deployment_manifest))
    workload_resources_info = resources_info.select { |resource_info|
      ["replicaset", "deployment", "statefulset", "pod", "daemonset"].includes?(resource_info[:kind].downcase)
    }
    total_resource_count = workload_resources_info.size
    current_resource_number = 1
    workload_resources_info.each do |resource_info|
      stdout_success "Waiting for resource for \"#{deployment_name}\" deployment (#{current_resource_number}/" +
                     "#{total_resource_count}): [#{resource_info[:kind]}] #{resource_info[:name]}",
        same_line: true

      ready = KubectlClient::Wait.resource_wait_for_install(resource_info[:kind],
        resource_info[:name], wait_count: timeout, namespace: resource_info[:namespace])
      if !ready
        stdout_failure "\"#{deployment_name}\" deployment installation has timed-out, [#{resource_info[:kind]}] " +
                       "#{resource_info[:name]} is not ready after #{timeout} seconds.", same_line: true
        stdout_failure "It is recommended to investigate the resource in the cluster, " +
                       "run cnf_uninstall, and then attempt to reinstall the CNF."
        exit 1
      end
      current_resource_number += 1
    end
    stdout_success "All \"#{deployment_name}\" deployment resources are up.", same_line: true
  end

  def self.wait_for_deployment_uninstallation(
    deployment_name : String,
    descendant_map  : Hash(ResourceInfo, Array(KubectlClient::ResourceDescendant)),
    timeout         : Int32
  ) : Bool
    # Separate normal resources vs. namespaces so namespaces run last
    roots, namespaces = descendant_map.partition { |res, _| res[:kind].downcase != "namespace" }
    ordered           = roots + namespaces
    total             = ordered.size
    all_deleted       = true

    ordered.each_with_index do |(res, descendants), idx|
      kind      = res[:kind]
      name      = res[:name]
      namespace = res[:namespace]

      stdout_success(
        "Waiting deletion for \"#{deployment_name}\" (#{idx+1}/#{total}): [#{kind}] #{name}",
        same_line: idx > 0
      )

      ok = KubectlClient::Wait.resource_wait_for_uninstall(
        kind, name, namespace, timeout, descendants
      )

      unless ok
        all_deleted = false
        stdout_failure(
          "\"#{deployment_name}\" uninstallation timed out: #{kind}/#{name} still present after #{timeout} seconds",
          same_line: true
        )
      end
    end

    if all_deleted
      stdout_success("All \"#{deployment_name}\" resources are gone.", same_line: true)
    else
      stdout_failure("Some resources of \"#{deployment_name}\" did not finish deleting within the timeout.")
    end

    all_deleted
  end
end
