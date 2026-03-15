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
    install_deployments(parsed_args: parsed_args, deployment_managers: deployment_managers, config: config)
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

  def self.install_deployments(parsed_args, deployment_managers, config)
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
      
      # Add to deployment-specific file without source comments
      Manifest.add_manifest_to_file(deployment_name, generated_deployment_manifest, deployment_manifest_path)
      
      # Add to common manifest WITH source comments
      # Determine deployment type based on class hierarchy
      deployment_type = case deployment_manager
      when ManifestDeploymentManager
        "manifest"
      when HelmDirectoryDeploymentManager
        "helm_directory"
      when HelmChartDeploymentManager
        "helm_chart"
      else
        "unknown"
      end
      
      deployment_ymls = Manifest.manifest_string_to_ymls(generated_deployment_manifest)
      manifest_with_source = Manifest.combine_ymls_with_deployment_source(deployment_ymls, deployment_name, deployment_type)
      Manifest.add_manifest_to_file(deployment_name, manifest_with_source, COMMON_MANIFEST_FILE_PATH)

      if !parsed_args[:skip_wait_for_install]
        wait_for_deployment_installation(deployment_name, generated_deployment_manifest, parsed_args[:timeout])
      end
    end

    # After all deployments are installed, fetch and add label-identified resources to the composite manifest
    if !parsed_args[:skip_wait_for_install]
      add_label_resources_to_manifest(config, parsed_args[:timeout])
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

    delete_workload_resources_by_labels(config)

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

  private def self.delete_workload_resources_by_labels(config)
    logger = Log.for("delete_workload_resources_by_labels")
    label_selectors = config.common.workload_resource_labels
    return if label_selectors.empty?

    label_selectors.each do |selector|
      key = selector.key
      value = selector.value
      next if key.empty? || value.empty?

      labels = {key => value}
      if selector.namespace.empty?
        logger.info { "Deleting workload resources by label #{key}=#{value} in all namespaces" }
        KubectlClient::WORKLOAD_RESOURCES.each do |_, kind|
          KubectlClient::Delete.resource(kind, labels: labels, extra_opts: "-A")
        end
      else
        logger.info { "Deleting workload resources by label #{key}=#{value} in namespace #{selector.namespace}" }
        KubectlClient::WORKLOAD_RESOURCES.each do |_, kind|
          KubectlClient::Delete.resource(kind, namespace: selector.namespace, labels: labels)
        end
      end
    end
  rescue ex
    Log.for("delete_workload_resources_by_labels").warn { "Label-based CNF uninstall cleanup failed: #{ex.message}" }
  end

  def self.wait_for_deployment_installation(deployment_name, deployment_manifest, timeout)
    resources_info = Helm.workload_resource_kind_names(Manifest.manifest_string_to_ymls(deployment_manifest))
    
    # Split resources into standard workload resources and custom resources
    workload_resources_info = resources_info.select { |resource_info|
      WORKLOAD_RESOURCE_KIND_NAMES.includes?(resource_info[:kind].downcase)
    }
    
    # List of standard Kubernetes resources that should NOT be treated as custom resources
    standard_k8s_resources = WORKLOAD_RESOURCE_KIND_NAMES + [
      "service", "configmap", "secret", "serviceaccount", 
      "role", "rolebinding", "clusterrole", "clusterrolebinding", 
      "namespace", "persistentvolumeclaim", "persistentvolume",
      "networkpolicy", "ingress", "endpoints", "limitrange", "resourcequota",
      "horizontalpodautoscaler", "poddisruptionbudget", "priorityclass",
      "storageclass", "volumeattachment", "csistoragecapacity", "csinode", "csidriver"
    ]
    
    # Custom resources (anything not a standard Kubernetes resource)
    custom_resources_info = resources_info.reject { |resource_info|
      standard_k8s_resources.includes?(resource_info[:kind].downcase)
    }
    
    # Wait for workload resources first
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

        # --- DEBUG INFO ---
        # Log deployment status, pod status, and pod logs at info level
        logger = Log.for("deployment_timeout_debug")
        if resource_info[:kind].downcase == "deployment"
          ns = resource_info[:namespace] || "default"
          deployment_status = `kubectl get deployment #{resource_info[:name]} -n #{ns} -o yaml 2>&1`
          logger.info { "--- Deployment status ---\n#{deployment_status}" }

          pods = `kubectl get pods -n #{ns} -l app=#{resource_info[:name]} -o name 2>&1`.split("\n")
          pods.each do |pod|
            pod_name = pod.split("/").last
            pod_status = `kubectl get pod #{pod_name} -n #{ns} -o yaml 2>&1`
            logger.info { "--- Pod status for #{pod_name} ---\n#{pod_status}" }
          end

          pods.each do |pod|
            pod_name = pod.split("/").last
            pod_logs = `kubectl logs #{pod_name} -n #{ns} --tail=40 2>&1`
            logger.info { "--- Logs for pod #{pod_name} ---\n#{pod_logs}" }
          end
        end
        # --- END DEBUG INFO ---
        exit 1
      end
      current_resource_number += 1
    end
    
    if workload_resources_info.size > 0
      stdout_success "All \"#{deployment_name}\" deployment resources are up.", same_line: true
    end
    
    # Wait for custom resources (e.g., CRDs) with Ready condition
    if custom_resources_info.size > 0
      total_custom_count = custom_resources_info.size
      current_custom_number = 1
      custom_resources_info.each do |resource_info|
        stdout_success "Waiting for custom resource for \"#{deployment_name}\" deployment (#{current_custom_number}/" +
                       "#{total_custom_count}): [#{resource_info[:kind]}] #{resource_info[:name]}",
          same_line: true

        ready = KubectlClient::Wait.resource_wait_for_install(resource_info[:kind],
          resource_info[:name], wait_count: timeout, namespace: resource_info[:namespace])
        if !ready
          stdout_failure "\"#{deployment_name}\" deployment installation has timed-out, custom resource [#{resource_info[:kind]}] " +
                         "#{resource_info[:name]} is not ready after #{timeout} seconds.", same_line: true
          stdout_failure "It is recommended to investigate the resource in the cluster, " +
                         "run cnf_uninstall, and then attempt to reinstall the CNF."
          exit 1
        end
        current_custom_number += 1
      end
      stdout_success "All \"#{deployment_name}\" deployment custom resources are ready.", same_line: true
    end
  end

  private def self.add_label_resources_to_manifest(config, timeout : Int32)
    logger = Log.for("add_label_resources_to_manifest")
    label_selectors = config.common.workload_resource_labels
    return if label_selectors.empty?

    # Make the sleep before label resource identification configurable
    label_resource_sleep = ENV.has_key?("CNF_TESTSUITE_LABEL_RESOURCE_SLEEP") ? ENV["CNF_TESTSUITE_LABEL_RESOURCE_SLEEP"].to_i : 5
    stdout_success "Identifying and adding label-selected resources to composite manifest."
    sleep label_resource_sleep.seconds
    start = Time.utc

    label_selectors.each do |selector|
      key = selector.key
      value = selector.value
      next if key.empty? || value.empty?

      namespace = selector.namespace.empty? ? nil : selector.namespace
      selector_str = "#{key}=#{value}"
      logger.info { "Fetching resources with label #{selector_str} in #{namespace || "all namespaces"}" }

      fetch_resources = -> do
        resources = [] of NamedTuple(kind: String, name: String, namespace: String)
        KubectlClient::WORKLOAD_RESOURCES.each do |_, kind|
          json = KubectlClient::Get.resource(kind, namespace: namespace, all_namespaces: namespace.nil?, selector: selector_str)
          items = (json.dig?("items").try &.as_a?) || [] of JSON::Any
          items.each do |item|
            res_namespace = (item.dig?("metadata", "namespace") || CLUSTER_DEFAULT_NAMESPACE).to_s
            resources << {kind: kind, name: item.dig("metadata", "name").as_s, namespace: res_namespace}
          end
        end
        resources
      end

      initial_resources = fetch_resources.call
      has_pods = initial_resources.any? { |res| res[:kind].downcase == "pod" }
      next unless has_pods

      seen = Set(String).new
      last_ready_time = Time.utc

      ok = repeat_with_timeout(timeout: timeout, errormsg: "Timed out waiting for labeled resources: #{selector_str}", delay: 1) do
        current_resources = fetch_resources.call
        new_resources = current_resources.reject do |res|
          seen.includes?("#{res[:namespace]},#{res[:kind]}/#{res[:name]}".downcase)
        end

        new_resources.each do |res|
          elapsed = (Time.utc - start).total_seconds.to_i
          remaining = timeout - elapsed
          if remaining <= 0
            logger.warn { "Timed out waiting for #{res[:kind]}/#{res[:name]} readiness" }
            stdout_failure "Label-selected resources did not become ready within #{timeout} seconds."
            exit 1
          end

          ready = KubectlClient::Wait.resource_wait_for_install(res[:kind], res[:name], remaining, res[:namespace])
          unless ready
            stdout_failure "Label-selected resource #{res[:kind]}/#{res[:name]} did not become ready."
            exit 1
          end
          seen.add("#{res[:namespace]},#{res[:kind]}/#{res[:name]}".downcase)
          last_ready_time = Time.utc
        end

        elapsed_since_last = (Time.utc - last_ready_time).total_seconds
        elapsed_since_last >= label_resource_sleep
      end

      unless ok
        stdout_failure "Timed out waiting for labeled resources: #{selector_str}"
        exit 1
      end
    end

    # Fetch all label-identified resources and add them to the composite manifest
    label_resource_ymls = fetch_workload_resources_by_labels(config, default_namespace: CLUSTER_DEFAULT_NAMESPACE)
    unless label_resource_ymls.empty?
      # Build label selector string for the comment
      workload_labels = config.common.workload_resource_labels
      label_selector = workload_labels.map { |l| "#{l.key}=#{l.value}" }.join(",")
      
      label_manifest = Manifest.combine_ymls_with_label_source(label_resource_ymls, label_selector)
      Manifest.add_manifest_to_file("label-identified-resources", label_manifest, COMMON_MANIFEST_FILE_PATH)
      logger.info { "Added #{label_resource_ymls.size} label-identified resources to composite manifest" }
      stdout_success "Added #{label_resource_ymls.size} label-identified resources to composite manifest."
    end
    
    # Fetch resources owned by CUSTOM resources only (not standard k8s resources)
    # Only go one level deep - don't recurse further
    all_manifest_resources = Manifest.manifest_path_to_ymls(COMMON_MANIFEST_FILE_PATH)
    
    # Build a set of existing resource UIDs to avoid duplicates
    existing_uids = all_manifest_resources.map do |resource|
      uid = resource.dig?("metadata", "uid")
      uid ? uid.as_s : nil
    end.compact.to_set
    
    # Filter to only custom resources (those with custom apiVersions)
    custom_resources = all_manifest_resources.select do |resource|
      is_custom_resource?(resource)
    end
    
    owned_resource_ymls = fetch_owned_resources_from_custom_resources(custom_resources, default_namespace: CLUSTER_DEFAULT_NAMESPACE)
    
    # Filter out resources that are already in the manifest
    new_owned_resources = owned_resource_ymls.reject do |resource|
      uid = resource.dig?("metadata", "uid")
      uid && existing_uids.includes?(uid.as_s)
    end
    
    unless new_owned_resources.empty?
      # Build owner map (not actually needed since we include owner info in the YAML itself)
      owner_map = {} of String => String
      
      owned_manifest = Manifest.combine_ymls_with_owner_source(new_owned_resources, owner_map)
      Manifest.add_manifest_to_file("owner-reference-resources", owned_manifest, COMMON_MANIFEST_FILE_PATH)
      logger.info { "Added #{new_owned_resources.size} owner-reference resources to composite manifest" }
      stdout_success "Added #{new_owned_resources.size} resources via ownerReferences to composite manifest."
    end
  end

  private def self.fetch_workload_resources_by_labels(config, default_namespace : String = CLUSTER_DEFAULT_NAMESPACE) : Array(YAML::Any)
    logger = Log.for("fetch_workload_resources_by_labels")
    label_selectors = config.common.workload_resource_labels
    return [] of YAML::Any if label_selectors.empty?

    resources = [] of YAML::Any
    seen_uids = Set(String).new

    label_selectors.each do |selector|
      key = selector.key
      value = selector.value
      next if key.empty? || value.empty?

      namespace = selector.namespace.empty? ? nil : selector.namespace
      selector_str = "#{key}=#{value}"
      matched_items = [] of JSON::Any

      KubectlClient::WORKLOAD_RESOURCES.each do |_, kind|
        logger.debug { "Fetching #{kind} resources by label #{selector_str} in #{namespace || "all namespaces"}" }
        json = KubectlClient::Get.resource(kind, namespace: namespace, all_namespaces: namespace.nil?, selector: selector_str)
        items = (json.dig?("items").try &.as_a?) || [] of JSON::Any
        items.each { |item| matched_items << item }
      end

      selected_kind_names = matched_items.map do |item|
        item.dig?("kind").try(&.as_s).to_s.downcase
      end.to_set

      matched_items.each do |item|
        kind = item.dig?("kind").try(&.as_s).to_s
        name = item.dig?("metadata", "name").try(&.as_s).to_s

        owner_refs = item.dig?("metadata", "ownerReferences").try(&.as_a?)
        owned_by_selected_kind = owner_refs ? owner_refs.any? do |owner_ref|
          owner_kind = owner_ref.dig?("kind").try(&.as_s).to_s.downcase
          selected_kind_names.includes?(owner_kind)
        end : false

        if owned_by_selected_kind
          logger.debug { "Skipping label-selected #{kind}/#{name} because owner kind is also label-selected for #{selector_str}" }
          next
        end

        uid = item.dig?("metadata", "uid").try(&.as_s)
        if uid && seen_uids.includes?(uid)
          logger.debug { "Skipping duplicate label-selected #{kind}/#{name} with uid #{uid}" }
          next
        end

        seen_uids.add(uid) if uid

        # Remove status field to avoid capturing runtime IPs and other dynamic data
        if item.as_h?
          item.as_h.delete("status")
        end
        yml = YAML.parse(item.to_json)
        resources << Helm.ensure_resource_with_namespace(yml, default_namespace)
      end
    end

    resources
  end

  # Check if a resource is a custom resource (not a standard Kubernetes resource)
  private def self.is_custom_resource?(resource : YAML::Any) : Bool
    api_version = resource.dig?("apiVersion")
    return false unless api_version
    
    api_version_str = api_version.as_s
    
    # Standard k8s apiVersions that should be excluded:
    # - "" (core/v1)
    # - "v1" (core resources)
    # - anything with "k8s.io"
    # - "apps/v1", "batch/v1", "networking.k8s.io/v1", etc.
    standard_prefixes = [
      "v1",
      "apps/",
      "batch/",
      "networking.k8s.io",
      "policy/",
      "rbac.authorization.k8s.io",
      "storage.k8s.io",
      "apiextensions.k8s.io",
      "admissionregistration.k8s.io",
      "scheduling.k8s.io",
      "coordination.k8s.io",
      "node.k8s.io",
      "discovery.k8s.io",
      "flowcontrol.apiserver.k8s.io"
    ]
    
    # If apiVersion matches any standard prefix, it's not a custom resource
    return false if standard_prefixes.any? { |prefix| api_version_str == prefix || api_version_str.starts_with?(prefix) }
    
    # Otherwise it's likely a custom resource
    true
  end

  private def self.fetch_owned_resources_from_custom_resources(owner_resources : Array(YAML::Any), default_namespace : String = CLUSTER_DEFAULT_NAMESPACE) : Array(YAML::Any)
    logger = Log.for("fetch_owned_resources_from_custom_resources")
    all_owned_resources = [] of YAML::Any
    
    logger.info { "Fetching resources owned by #{owner_resources.size} custom resources (no recursion)" }
    
    # Extract or fetch UIDs from custom resources
    owner_uids = owner_resources.map do |resource|
      # Try to get UID from the resource
      uid = resource.dig?("metadata", "uid")
      if uid
        uid.as_s
      else
        # If no UID in manifest (it's a template), fetch it from the cluster
        kind = resource.dig?("kind").try(&.as_s)
        name = resource.dig?("metadata", "name").try(&.as_s)
        namespace_val = resource.dig?("metadata", "namespace")
        namespace = namespace_val ? namespace_val.as_s : default_namespace
        
        if kind && name
          begin
            cluster_resource = KubectlClient::Get.resource(kind, name, namespace)
            cluster_uid = cluster_resource.dig?("metadata", "uid")
            cluster_uid ? cluster_uid.as_s : nil
          rescue ex
            logger.debug { "Could not fetch #{kind}/#{name} from cluster: #{ex.message}" }
            nil
          end
        else
          nil
        end
      end
    end.compact
    
    return all_owned_resources if owner_uids.empty?
    
    # Search for resources directly owned by these custom resources (one level only)
    logger.debug { "Searching for resources owned by #{owner_uids.size} custom resource UIDs" }
    
    owner_uids.each do |owner_uid|
      # Search for resources that have this UID in their ownerReferences
      owned_resources = fetch_resources_by_owner_uid(owner_uid, default_namespace)
      
      owned_resources.each do |owned_resource|
        all_owned_resources << owned_resource
        
        kind = owned_resource.dig?("kind").try(&.as_s) || "Unknown"
        name = owned_resource.dig?("metadata", "name").try(&.as_s) || "unknown"
        owned_uid = owned_resource.dig?("metadata", "uid").try(&.as_s) || "unknown"
        logger.debug { "Found owned resource: #{kind}/#{name} with uid #{owned_uid}" }
      end
    end
    
    logger.info { "Found #{all_owned_resources.size} resources owned by custom resources (non-recursive)" }
    all_owned_resources
  end

  private def self.fetch_resources_by_owner_uid(owner_uid : String, default_namespace : String = CLUSTER_DEFAULT_NAMESPACE) : Array(YAML::Any)
    logger = Log.for("fetch_resources_by_owner_uid")
    resources = [] of YAML::Any
    
    # Search across all configured workload resource kinds so ownerReference
    # discovery stays aligned with workload processing logic.
    workload_resource_map = KubectlClient::WORKLOAD_RESOURCES.to_h
    searchable_kinds = [] of String
    workload_resource_map.each do |key, value|
      searchable_kinds << value if WORKLOAD_RESOURCE_KIND_NAMES.includes?(key.to_s)
    end
    
    searchable_kinds.each do |kind|
      begin
        logger.debug { "Searching #{kind} resources for ownerReferences to UID #{owner_uid}" }
        # Get all resources of this kind across all namespaces
        json = KubectlClient::Get.resource(kind, namespace: nil, all_namespaces: true)
        items = (json.dig?("items").try &.as_a?) || [] of JSON::Any
        
        items.each do |item|
          # Check if this resource has ownerReferences
          owner_refs = item.dig?("metadata", "ownerReferences")
          next unless owner_refs
          
          owner_refs_array = owner_refs.as_a?
          next unless owner_refs_array
          
          # Check if any ownerReference matches the target UID
          has_matching_owner = owner_refs_array.any? do |owner_ref|
            owner_ref.dig?("uid").try(&.as_s) == owner_uid
          end
          
          if has_matching_owner
            # Remove status field to avoid capturing runtime IPs and other dynamic data
            if item.as_h?
              item.as_h.delete("status")
            end
            yml = YAML.parse(item.to_json)
            resources << Helm.ensure_resource_with_namespace(yml, default_namespace)
            
            res_kind = item.dig?("kind").try(&.as_s) || "Unknown"
            res_name = item.dig?("metadata", "name").try(&.as_s) || "unknown"
            logger.debug { "Found owned #{res_kind}/#{res_name}" }
          end
        end
      rescue ex
        logger.debug { "Error fetching #{kind} resources: #{ex.message}" }
      end
    end
    
    resources
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
