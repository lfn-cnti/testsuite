# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "json"
require "../utils/utils.cr"

rolling_version_change_test_names = ["rolling_update", "rolling_downgrade", "rolling_version_change"]

desc "Configuration should be managed in a declarative manner, using ConfigMaps, Operators, or other declarative interfaces."

category_task "configuration", [
    "nodeport_not_used",
    "hostport_not_used",
    "hardcoded_ip_addresses_in_k8s_runtime_configuration",
    "secrets_used",
    "immutable_configmap",
    "alpha_k8s_apis",
    "require_labels",
    "latest_tag",
    "default_namespace",
    "operator_installed",
    "versioned_tag"
  ]

desc "Check if the CNF is running containers with labels configured?"
scored_task "require_labels",
  emoji: "🏷️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install
    policy_path = Kyverno.best_practice_policy("require-labels/require-labels.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

    resource_keys = CNFManager.workload_resource_keys(args, config)
    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)

    if failures.size == 0
      result.passed("Pods have the app.kubernetes.io/name label")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: failure.message)
        end
      end
      result.failed("Pods should have the app.kubernetes.io/name label.")
    end
  end
end

desc "Check if the CNF installs resources in the default namespace"
scored_task "default_namespace",
  emoji: "🏷️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install
    policy_path = Kyverno.best_practice_policy("disallow-default-namespace/disallow-default-namespace.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

    resource_keys = CNFManager.workload_resource_keys(args, config)
    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)

    if failures.size == 0
      result.passed("default namespace is not being used")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          result.add_impacted_resource(resource.kind, resource.name, "default", reason: failure.message)
        end
      end
      result.failed("Resources are created in the default namespace")
    end
  end
end

desc "Check if the CNF uses container images with the latest tag"
scored_task "latest_tag",
  type: CNFManager::TestType::Essential,
  emoji: "🏷️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    Kyverno.install

    policy_path = Kyverno.best_practice_policy("disallow-latest-tag/disallow-latest-tag.yaml")
    failures = Kyverno::PolicyAudit.run(policy_path, EXCLUDE_NAMESPACES)

    resource_keys = CNFManager.workload_resource_keys(args, config)
    failures = Kyverno.filter_failures_for_cnf_resources(resource_keys, failures)

    if failures.size == 0
      result.passed("Container images are not using the latest tag")
    else
      failures.each do |failure|
        failure.resources.each do |resource|
          images = Kyverno::Findings.latest_tag_images(resource.kind, resource.name, resource.namespace)
          if images.empty?
            result.add_impacted_resource(resource.kind, resource.name, resource.namespace, reason: "using the latest tag. #{failure.message}")
          else
            images.each do |i|
              result.add_impacted_resource(resource.kind, resource.name, resource.namespace, container: i[:container], reason: "image #{i[:image]} uses the latest tag")
            end
          end
        end
      end
      result.failed("Container images are using the latest tag")
    end
  end
end

desc "Do all cnf images have versioned tags?"
scored_task "versioned_tag",
  deps: ["install_opa"],
  emoji: "🏷️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    fail_msgs = [] of String
    task_response = CNFManager.workload_resource_test(args, config) do |resource, _, _|
      test_passed = true
      resource_yaml = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      pods = KubectlClient::Get.pods_by_resource_labels(resource_yaml, namespace: resource[:namespace])
      pods.map do |pod|
        pod_name = pod.dig("metadata", "name")

        if OPA.find_non_versioned_pod(pod_name.as_s)
          if resource[:kind] == "pod"
            fail_msg = "Pod/#{resource[:name]} in #{resource[:namespace]} namespace does not use a versioned image"
          else
            fail_msg = "Pod/#{pod_name} in #{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]} namespace does not use a versioned image"
          end

          unless fail_msgs.find{|x| x== fail_msg}
            fail_msgs << fail_msg
          end

          test_passed = false
        end
      end

      test_passed
    end

    if task_response
      result.passed("Container images use versioned tags")
    else
      fail_msgs.each do |msg|
        result.append_description(msg)
      end
      result.failed("Container images do not use versioned tags")
    end
  end
end

desc "Does the CNF use NodePort"
scored_task "nodeport_not_used" do |t, args|
  # TODO rename task_runner to multi_cnf_task_runner
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    test_passed = true

    CNFManager.resource_refs(args, config, ["service"]) do |resource|
      Log.for(t.name).info { "nodeport_not_used resource: #{resource}" }
      service = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      Log.for(t.name).debug { "service: #{service}" }
      service_type = service.dig?("spec", "type")
      Log.for(t.name).info { "service_type: #{service_type}" }
      if service_type == "NodePort"
        #TODO make a service selector and display the related resources
        # that are tied to this service
        result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace], reason: "using a NodePort")
        test_passed = false
      end
    end

    if test_passed
      result.passed("NodePort is not used")
    else
      result.failed("NodePort is being used")
    end
  end
end

desc "Does the CNF use HostPort"
scored_task "hostport_not_used",
  type: CNFManager::TestType::Essential do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      Log.for(t.name).info { "hostport_not_used resource: #{resource}" }
      test_passed = true

      # per example https://github.com/lfn-cnti/testsuite/issues/164#issuecomment-904890977
      KubectlClient::Get.resource_all_containers(resource[:kind], resource[:name], resource[:namespace]).each do |single_container|
        container_name = single_container.dig?("name").try(&.as_s) || ""
        single_container.dig?("ports").try(&.as_a?).try &.each do |single_port|
          hostport = single_port.dig?("hostPort")
          Log.for(t.name).debug { "container #{container_name} port #{single_port}: hostPort #{hostport}" }
          if hostport
            container_port = single_port.dig?("containerPort")
            result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace], container: container_name,
              reason: "using hostPort #{hostport} for containerPort #{container_port}")
            test_passed = false
          end
        end
      end
      test_passed
    end
    if task_response
      result.passed("HostPort is not used")
    else
      result.failed("HostPort is being used")
    end
  end
end

# The YAML documents of a multi-document manifest with the line range each
# occupies (1-based, inclusive) and its kind/name/namespace when parseable.
def manifest_documents(lines : Array(String)) : Array(NamedTuple(first_line: Int32, last_line: Int32, kind: String?, name: String?, namespace: String?))
  documents = [] of NamedTuple(first_line: Int32, last_line: Int32, kind: String?, name: String?, namespace: String?)
  start = 0
  flush = ->(last : Int32) do
    chunk = lines[start..last]
    unless chunk.all?(&.strip.empty?)
      kind = name = namespace = nil
      begin
        parsed = YAML.parse(chunk.join("\n"))
        kind = parsed.dig?("kind").try(&.as_s?)
        name = parsed.dig?("metadata", "name").try(&.as_s?)
        namespace = parsed.dig?("metadata", "namespace").try(&.as_s?)
      rescue
        # a document that does not parse still gets its line range
      end
      documents << {first_line: start + 1, last_line: last + 1, kind: kind, name: name, namespace: namespace}
    end
  end
  lines.each_with_index do |line, index|
    if line.strip == "---"
      flush.call(index - 1) if index > start
      start = index + 1
    end
  end
  flush.call(lines.size - 1) if start < lines.size
  documents
end

desc "Does the CNF have hardcoded IPs in the K8s resource configuration"
scored_task "hardcoded_ip_addresses_in_k8s_runtime_configuration",
  type: CNFManager::TestType::Essential do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    allowed_ip_addresses = [
      "127.0.0.1",
      "0.0.0.0"
    ]
    hardcoded_ip_exceptions = config.common.hardcoded_ip_exceptions

    # The composite manifest is scanned line by line; each hit is attributed to
    # the YAML document it sits in, so the result names the resource - the
    # manifest's line numbers alone mean nothing to the CNF's author.
    lines = File.read_lines(COMMON_MANIFEST_FILE_PATH)
    documents = manifest_documents(lines)
    ip_adress_regex = /((?:\d{1,3}\.){3}\d{1,3})(?:\/(\d{1,2}))?/
    found_violations = [] of NamedTuple(line_number: Int32, line: String, ip: String)
    lines.each_with_index do |line, index|
      break if line.matches?(/NOTES:/)
      line.scan(ip_adress_regex).each do |match|
        ip = match[1]
        cidr_suffix = match[2]?
        next if allowed_ip_addresses.includes?(ip) || hardcoded_ip_exceptions.any? { |e| e.ip == ip } || cidr_suffix
        found_violations << {line_number: index + 1, line: line.strip, ip: ip}
      end
    end

    if found_violations.empty?
      result.passed("No hard-coded IP addresses found in the runtime K8s configuration")
    else
      result.append_description("Hard-coded IP addresses found in #{COMMON_MANIFEST_FILE_PATH}")
      found_violations.each do |violation|
        doc = documents.find { |d| d[:first_line] <= violation[:line_number] && violation[:line_number] <= d[:last_line] }
        reason = "hard-coded IP #{violation[:ip]} at line #{violation[:line_number]}: #{violation[:line]}"
        if doc && doc[:kind] && doc[:name]
          result.add_impacted_resource(doc[:kind].to_s, doc[:name].to_s, doc[:namespace], reason: reason)
        else
          result.add_impacted_resource("Manifest", File.basename(COMMON_MANIFEST_FILE_PATH), reason: reason)
        end
      end
      result.append_remediation("Replace hard-coded IP addresses with Service names, DNS names or configuration that is resolved at deploy time. An address that must stay literal can be declared under `common.hardcoded_ip_exceptions` in cnti-testsuite.yaml so this test accepts it.")
      result.failed("Hard-coded IP addresses found in the runtime K8s configuration")
    end
  end
end

desc "Does the CNF use K8s Secrets?"
scored_task "secrets_used",
  type: CNFManager::TestType::Bonus,
  emoji: "🧫" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Parse the cnti-testsuite.yaml
    resp = ""
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, volumes|
      Log.for(t.name).info { "resource: #{resource}" }
      Log.for(t.name).info { "volumes: #{volumes}" }

      volume_test_passed = false
      container_secret_mounted = false
      # Check to see any volume secrets are actually used
      volumes.as_a.each do |secret_volume|
        if secret_volume["secret"]?
          Log.for(t.name).info { "secret_volume: #{secret_volume["name"]}" }
          container_secret_mounted = false
          containers.as_a.each do |container|
            if container["volumeMounts"]?
                vmount = container["volumeMounts"].as_a
              Log.for(t.name).info { "vmount: #{vmount}" }
              Log.for(t.name).debug { "container[env]: #{container["env"]}" }
              if (vmount.find { |x| x["name"] == secret_volume["name"]? })
                Log.for(t.name).debug { secret_volume["name"] }
                container_secret_mounted = true
                volume_test_passed = true
              end
            end
          end
          # If any secret volume exists, and it is not mounted by a
          # container, issue a warning
          unless container_secret_mounted
            result.append_description("Warning: secret volume #{secret_volume["name"]} not mounted")
          end
        end
      end

      #  if there are any containers that have a secretkeyref defined
      #  but do not have a corresponding k8s secret defined, this
      #  is an installation problem, and does not stop the test from passing

      namespace = resource[:namespace]
      secrets = KubectlClient::Get.resource("secrets", namespace: namespace)

      secrets["items"].as_a.each do |s|
        s_name = s["metadata"]["name"]
        s_type = s["type"]
        s_namespace = s.dig("metadata", "namespace")
        Log.for(t.name).debug {"secret name: #{s_name}, type: #{s_type}, namespace: #{s_namespace}"}
      end
      secret_keyref_found_and_not_ignored = false
      containers.as_a.each do |container|
        c_name = container["name"]
        Log.for(t.name).debug { "container: #{c_name} envs #{container["env"]?}" }
        if container["env"]?
          Log.for("container_info").info { container["env"] }
          container["env"].as_a.find do |env|
            Log.for(t.name).trace { "checking container: #{c_name}" }
            secret_keyref_found_and_not_ignored = secrets["items"].as_a.find do |s|
              s_name = s["metadata"]["name"]
              if IGNORED_SECRET_TYPES.includes?(s["type"])
                Log.debug { "container: #{c_name} ignored secret: #{s_name}" }
                next
              end
              Log.for(t.name).info { "Checking secret: #{s_name}" }
              found = (s_name == env.dig?("valueFrom", "secretKeyRef", "name"))
              if found
                Log.for(t.name).info { "secret_reference_found. container: #{c_name} found secret reference: #{s_name}" }
              end
              found
            end
          end
        end
      end

      # Always pass if any workload resource in a cnf uses a (non-exempt) secret.
      # If the  workload resource does not use a (non-exempt) secret, always skip.

      test_passed = false
      if secret_keyref_found_and_not_ignored || volume_test_passed
        test_passed = true
      end

      unless test_passed
        result.append_description("No Secret Volumes or Container secretKeyRefs found for resource: #{resource}")
      end
      test_passed
    end
    if task_response
      result.passed("Secrets defined and used")
    else
      result.append_remediation("To address this issue please see the USAGE.md documentation")
      result.skipped("Secrets not used")
    end
  end
end

# https://www.cloudytuts.com/tutorials/kubernetes/how-to-create-immutable-configmaps-and-secrets/
class ImmutableConfigMapTemplate
  def initialize(@test_url : String)
  end

  ECR.def_to_s("src/templates/immutable_configmap.yml.ecr")
end

alias MutableConfigMapsInEnvResult = NamedTuple(
  resource: NamedTuple(kind: String, name: String, namespace: String),
  container: String,
  configmap: String
)

alias MutableConfigMapsVolumesResult = NamedTuple(
  resource: NamedTuple(kind: String, name: String, namespace: String),
  container: String?,
  volume: String,
  configmap: String
)

def configmap_volume_mounted?(configmap_volume, container)
  return false if !container["volumeMounts"]?

  volume_mounts = container["volumeMounts"].as_a
  Log.for("container_volume_mounts").info { volume_mounts }
  result = volume_mounts.find { |x| x["name"] == configmap_volume["name"]? }
  return true if result
  false
end

def mutable_configmaps_as_volumes(
  resource : NamedTuple(kind: String, name: String, namespace: String),
  configmaps : Array(JSON::Any),
  volumes : Array(JSON::Any),
  containers : Array(JSON::Any)
) : Array(MutableConfigMapsVolumesResult)
  Log.for("immutable_configmap").info { "Resource: #{resource}; Volume count: #{volumes.size}" }

  # Select all configmap volumes
  configmap_volumes = volumes.select do |volume|
    volume["configMap"]?
  end

  Log.for("immutable_configmap").info { "Volume count for configmaps: #{volumes.size}" }
  Log.for("immutable_configmap").info { "Will loop through configmap volumes" }
  configmap_volumes.flat_map do |volume|
    Log.for("immutable_configmap:volume_item").info {volume}
    # Find the configmap that the volume is using
    configmap = configmaps.find{ |cm| cm["metadata"]["name"] == volume["configMap"]["name"]}
    Log.for("immutable_configmap:configmap_item").info {configmap}
    # Move on if the volume does not point to a valid configmap
    if !configmap
      next nil
    end

    containers.map do |container|
      # If configmap is immutable, then move on.
      if configmap["immutable"]? && configmap["immutable"] == true
        next nil
      end

      # If (configmap does not have immutable key OR configmap has immutable=false)
      if (!configmap["immutable"]? || (configmap["immutable"]? && configmap["immutable"] == false))
        Log.for("immutable_configmap_fail_volume").info { configmap }
        if configmap_volume_mounted?(volume, container)
          {resource: resource, container: container.dig("name").as_s, volume: volume["name"].as_s, configmap: configmap["metadata"]["name"].as_s}
        else
          {resource: resource, container: nil, volume: volume["name"].as_s, configmap: configmap["metadata"]["name"].as_s}
        end
      end
    end.compact
  end.compact
end

def container_env_configmap_refs(
  resource : NamedTuple(kind: String, name: String, namespace: String),
  configmaps : Array(JSON::Any),
  container : JSON::Any
) : Nil | Array(MutableConfigMapsInEnvResult)
  return nil if !container["env"]?

  Log.info { "container config_maps #{container["env"]?}" }
  container["env"].as_a.map do |item|
    # https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#define-container-environment-variables-with-data-from-multiple-configmaps
    env_configmap_ref = item.dig?("valueFrom", "configMapKeyRef", "name")
    next nil if env_configmap_ref == nil
    configmap = configmaps.find { |s| s["metadata"]["name"] == env_configmap_ref }
    next nil if configmap == nil

    if configmap && (!configmap["immutable"]? || (configmap["immutable"]? && configmap["immutable"] == false))
      Log.for("immutable_configmap_fail_env").info { configmap }
      {resource: resource, container: container.dig("name").as_s, configmap: configmap["metadata"]["name"].as_s}
    end
  end.compact
end

desc "Does the CNF use immutable configmaps?"
scored_task "immutable_configmap",
  type: CNFManager::TestType::Bonus,
  emoji: "⚖️" do |t, args|
  resp = ""

  task_response = CNFManager::Task.task_runner(args, task: t) do |args, config, result|

    # https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/

    # feature test to see if immutable_configmaps are enabled
    # https://github.com/lfn-cnti/testsuite/issues/508#issuecomment-758438413

    test_config_map_filename = "#{CNF_TEMP_FILES_DIR}/test_config_map.yml";

    template = ImmutableConfigMapTemplate.new("doesnt_matter").to_s
    Log.for(t.name).debug { "test immutable_configmap template: #{template}" }
    File.write(test_config_map_filename, template)
    KubectlClient::Apply.file(test_config_map_filename)

    # now we change then apply again

    template = ImmutableConfigMapTemplate.new("doesnt_matter_again").to_s
    Log.for(t.name).debug { "test immutable_configmap change template: #{template}" }
    File.write(test_config_map_filename, template)

    immutable_configmap_supported = true
    immutable_configmap_enabled = true

    # if the reapply with a change succedes immutable configmaps is NOT enabled
    # if KubectlClient::Apply.file(test_config_map_filename) == 0
    begin
      KubectlClient::Apply.file(test_config_map_filename)
    rescue ex : KubectlClient::ShellCMD::UnspecifiedError
      Log.for(t.name).info { "immutable configmaps supported, continuing with test" }
    else
      # Delete configmap immediately to avoid interfering with further tests
      begin
        KubectlClient::Delete.file(test_config_map_filename)
      rescue ex: KubectlClient::ShellCMD::NotFoundError
        Log.warn { "Cannot delete #{test_config_map_filename}. File not found." }
      end

      Log.for(t.name).info { "kubectl apply on immutable configmap succeeded for: #{test_config_map_filename}" }
      k8s_ver = KubectlClient.server_version
      if version_less_than(k8s_ver, "1.19.0")
        result.skipped("immutable configmaps are not supported in this k8s cluster")
      else
        result.failed("immutable configmaps are not enabled in this k8s cluster")
      end
      next
    end

    volumes_test_results = [] of MutableConfigMapsVolumesResult
    envs_with_mutable_configmap = [] of MutableConfigMapsInEnvResult

    cnf_manager_workload_resource_task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, volumes|
      Log.for(t.name).info { "resource: #{resource}" }
      Log.for(t.name).info { "volumes: #{volumes}" }

      # If the install type is manifest, the namesapce would be in the manifest.
      # Else rely on config for helm-based install
      namespace = resource[:namespace]
      configmaps = KubectlClient::Get.resource("configmaps", namespace: namespace)
      if configmaps.dig?("items")
        configmaps = configmaps.dig("items").as_a
      else
        configmaps = [] of JSON::Any
      end

      volumes_test_results = mutable_configmaps_as_volumes(resource, configmaps, volumes.as_a, containers.as_a)
      envs_with_mutable_configmap = containers.as_a.flat_map do |container|
        container_env_configmap_refs(resource, configmaps, container)
      end.compact

      Log.for("immutable_configmap_volumes").info { volumes_test_results }
      Log.for("immutable_configmap_envs").info { envs_with_mutable_configmap }

      volumes_test_results.size == 0 && envs_with_mutable_configmap.size == 0
    end

    if cnf_manager_workload_resource_task_response
      result.passed("All volume or container mounted configmaps immutable")
    elsif immutable_configmap_supported

      # Print out any mutable configmaps mounted as volumes
      volumes_test_results.each do |vol_result|
        msg = ""
        if vol_result[:resource] == nil
          msg = "Mutable configmap #{vol_result[:configmap]} used as volume in #{vol_result[:resource][:kind]}/#{vol_result[:resource][:name]} in #{vol_result[:resource][:namespace]} namespace."
        else
          msg = "Mutable configmap #{vol_result[:configmap]} mounted as volume #{vol_result[:volume]} in #{vol_result[:container]} container part of #{vol_result[:resource][:kind]}/#{vol_result[:resource][:name]} in #{vol_result[:resource][:namespace]} namespace."
        end
        result.append_description(msg)
      end
      envs_with_mutable_configmap.each do |env_result|
        msg = "Mutable configmap #{env_result[:configmap]} used in env in #{env_result[:container]} part of #{env_result[:resource][:kind]}/#{env_result[:resource][:name]} in #{env_result[:resource][:namespace]}."
        result.append_description(msg)
      end
      result.failed("Found mutable configmap(s)")
    end
  end
end

desc "Check if CNF uses Kubernetes alpha APIs"
scored_task "alpha_k8s_apis",
  emoji: "⭕🔍" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    offenders = 0
    CNFManager.cnf_resources(args, config) do |resource|
      api_version = resource.dig?("apiVersion").try(&.as_s?)
      kind = resource.dig?("kind").try(&.as_s?)
      name = resource.dig?("metadata", "name").try(&.as_s?)
      namespace = resource.dig?("metadata", "namespace").try(&.as_s?)
      next unless api_version && kind && name

      if api_version.split("/").last.includes?("alpha")
        offenders += 1
        result.add_impacted_resource(kind, name, namespace, reason: "declared with the alpha API #{api_version}")
      elsif kind == "CustomResourceDefinition"
        served = resource.dig?("spec", "versions").try(&.as_a?).try(&.compact_map do |version|
          next if version.dig?("served").try(&.as_bool?) == false
          version.dig?("name").try(&.as_s?)
        end) || [] of String
        if !served.empty? && served.all?(&.includes?("alpha"))
          offenders += 1
          result.add_impacted_resource(kind, name, namespace, reason: "serves only alpha version(s): #{served.join(", ")}")
        end
      end
    end

    if offenders.zero?
      result.passed("CNF does not use Kubernetes alpha APIs")
    else
      result.failed("CNF uses Kubernetes alpha APIs")
    end
  end
end

desc "Does the CNF install an Operator with OLM?"
scored_task "operator_installed",
  type: CNFManager::TestType::Bonus,
  emoji: "⚖️👀" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    subscription_names = CNFManager.cnf_resources(args, config) do |resource|
      kind = resource.dig("kind").as_s
      if kind && kind.downcase == "subscription"
        { "name" => resource.dig("metadata", "name"), "namespace" => resource.dig("metadata", "namespace") }
      end
    end.compact

    Log.for(t.name).info { "Subscription Names: #{subscription_names}" }


    #TODO Warn if csv is not found for a subscription.
    csv_names = subscription_names.map do |subscription|
      csv_created = nil
      resource_created = false

      KubectlClient::Wait.wait_for_resource_key_value("sub", "#{subscription["name"]}", {"status", "installedCSV"}, namespace: subscription["namespace"].as_s)

      installed_csv = KubectlClient::Get.resource("sub", "#{subscription["name"]}", "#{subscription["namespace"]}")
      if installed_csv.dig?("status", "installedCSV")
        { "name" => installed_csv.dig("status", "installedCSV"), "namespace" => installed_csv.dig("metadata", "namespace") }
      end
    end.compact

    Log.for(t.name).info { "CSV Names: #{csv_names}" }


    succeeded = csv_names.map do |csv| 
      if KubectlClient::Wait.wait_for_resource_key_value("csv", "#{csv["name"]}", {"status", "reason"}, namespace: csv["namespace"].as_s, value: "InstallSucceeded" ) && KubectlClient::Wait.wait_for_resource_key_value("csv", "#{csv["name"]}", {"status", "phase"}, namespace: csv["namespace"].as_s, value: "Succeeded" )
        csv_succeeded=true
      end
      csv_succeeded
    end

    Log.for(t.name).info { "Succeeded CSV Names: #{succeeded}" }

    if succeeded.size > 0 && succeeded.all?(true)
      Log.for(t.name).info { "Succeeded All True?" }
      result.passed("Operator is installed: 🐜")
    else
      result.na("No Operators Found 🦖")
    end
  end
end
