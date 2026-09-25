# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "json"
require "../utils/utils.cr"
require "../utils/image_tag.cr"

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
  emoji: "🏷️" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Read from the workload's own containers, no policy engine in between
    # (#2599): an image is versioned when it is pinned by digest or by a
    # tag that is not "latest" and names a version (see ImageTag).
    unversioned = 0
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _|
      image = container["image"]?.try(&.as_s?) || ""
      name = container["name"]?.try(&.as_s?) || "?"
      reason = ImageTag.unversioned_reason(image)
      if reason
        unversioned += 1
        result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace], container: name, reason: "image #{image} #{reason}")
        false
      else
        result.append_description("#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]} container #{name}: #{image} is versioned")
        true
      end
    end

    if task_response
      result.passed("Container images use versioned tags")
    else
      result.append_remediation("Pin every image to a release tag that names a version (or to a digest); avoid latest, untagged images and moving tags such as stable or main, which cannot be tracked or rolled back.")
      result.failed("#{unversioned} container image(s) do not use versioned tags")
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
    # A CustomResourceDefinition is a schema, not configuration: it is in the
    # manifest so the suite knows the CNF's custom resource kinds, and its
    # description strings carry RFC section numbers and OIDs that look like
    # addresses. Its lines are not scanned.
    unscanned_lines = Set(Int32).new
    documents.each do |doc|
      next unless doc[:kind] == "CustomResourceDefinition"
      (doc[:first_line]..doc[:last_line]).each { |line_number| unscanned_lines << line_number }
    end
    ip_adress_regex = /((?:\d{1,3}\.){3}\d{1,3})(?:\/(\d{1,2}))?/
    found_violations = [] of NamedTuple(line_number: Int32, line: String, ip: String)
    lines.each_with_index do |line, index|
      break if line.matches?(/NOTES:/)
      next if unscanned_lines.includes?(index + 1)
      line.scan(ip_adress_regex).each do |match|
        ip = match[1]
        cidr_suffix = match[2]?
        # Four dot-separated numbers are an address only when each is an octet.
        next unless ip.split(".").all? { |octet| octet.to_i <= 255 }
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
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/
    # Feature probe: an immutable ConfigMap must reject a change. Whether the
    # cluster enforces that is a cluster property, so a cluster that does not
    # makes the test not applicable (#2595). The probe is removed either way.
    test_config_map_filename = "#{CNF_TEMP_FILES_DIR}/test_config_map.yml"
    File.write(test_config_map_filename, ImmutableConfigMapTemplate.new("doesnt_matter").to_s)
    KubectlClient::Apply.file(test_config_map_filename)
    File.write(test_config_map_filename, ImmutableConfigMapTemplate.new("doesnt_matter_again").to_s)
    enforced = begin
      KubectlClient::Apply.file(test_config_map_filename)
      false
    rescue KubectlClient::ShellCMD::UnspecifiedError
      true
    end
    begin
      KubectlClient::Delete.file(test_config_map_filename)
    rescue KubectlClient::ShellCMD::NotFoundError
      Log.for(t.name).warn { "Probe ConfigMap already gone" }
    end
    unless enforced
      result.na("Immutable ConfigMaps are not enforced in this cluster: a change to one was accepted, so the test cannot apply here")
      next
    end

    # Findings are collected across every workload resource; they used to be
    # overwritten per resource, so only the last workload's were reported.
    volume_findings = [] of MutableConfigMapsVolumesResult
    env_findings = [] of MutableConfigMapsInEnvResult

    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, volumes|
      namespace = resource[:namespace]
      configmaps = KubectlClient::Get.resource("configmaps", namespace: namespace).dig?("items").try(&.as_a?) || [] of JSON::Any

      in_volumes = mutable_configmaps_as_volumes(resource, configmaps, volumes.as_a, containers.as_a)
      in_envs = containers.as_a.flat_map { |container| container_env_configmap_refs(resource, configmaps, container) }.compact
      volume_findings.concat(in_volumes)
      env_findings.concat(in_envs)
      in_volumes.empty? && in_envs.empty?
    end

    if task_response
      result.passed("All volume or container mounted configmaps immutable")
    else
      volume_findings.each do |f|
        where = f[:container] ? "mounted as volume #{f[:volume]} in container #{f[:container]}" : "used as volume #{f[:volume]}"
        result.add_impacted_resource(f[:resource][:kind], f[:resource][:name], f[:resource][:namespace],
          container: f[:container], reason: "ConfigMap #{f[:configmap]} #{where} is mutable")
      end
      env_findings.each do |f|
        result.add_impacted_resource(f[:resource][:kind], f[:resource][:name], f[:resource][:namespace],
          container: f[:container], reason: "ConfigMap #{f[:configmap]} used in env of container #{f[:container]} is mutable")
      end
      result.append_remediation("Set immutable: true on ConfigMaps that hold non-mutable data; changing one then means creating a new ConfigMap and rolling the workload to it.")
      result.failed("Found #{volume_findings.size + env_findings.size} mutable configmap use(s)")
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

    if subscription_names.empty?
      # Informational only: without OLM Subscriptions there is no operator to
      # verify, and non-OLM operators are out of scope for this test.
      result.na("No Operators Found: the CNF is not operator-managed")
      next
    end

    findings = [] of NamedTuple(kind: String, name: String, namespace: String, reason: String)

    csv_names = subscription_names.compact_map do |subscription|
      sub_name = subscription["name"].as_s
      sub_ns = subscription["namespace"].as_s

      # OLM resolves a Subscription to a ClusterServiceVersion in the
      # Subscription's own namespace; a timeout is a finding, not a crash.
      unless KubectlClient::Wait.wait_for_resource_key_value("sub", sub_name, {"status", "installedCSV"}, namespace: sub_ns, wait_count: RESOURCE_CREATION_TIMEOUT)
        findings << {kind: "Subscription", name: sub_name, namespace: sub_ns, reason: "no installedCSV after #{RESOURCE_CREATION_TIMEOUT}s"}
        next nil
      end

      installed_csv = KubectlClient::Get.resource("sub", sub_name, sub_ns).dig("status", "installedCSV").as_s
      {name: installed_csv, namespace: sub_ns}
    end

    Log.for(t.name).info { "CSV Names: #{csv_names}" }

    csv_names.each do |csv|
      # An operator is installed once its CSV reports phase Succeeded.
      unless KubectlClient::Wait.wait_for_resource_key_value("csv", csv[:name], {"status", "phase"}, namespace: csv[:namespace], value: "Succeeded", wait_count: RESOURCE_CREATION_TIMEOUT)
        findings << {kind: "ClusterServiceVersion", name: csv[:name], namespace: csv[:namespace], reason: "phase is not Succeeded after #{RESOURCE_CREATION_TIMEOUT}s"}
        next
      end

      # A CSV in phase Succeeded can still have a broken operator Deployment;
      # the Deployments its install strategy creates must be ready.
      operator_deployments(csv[:name], csv[:namespace]).each do |dep_name|
        unless KubectlClient::Wait.resource_wait_for_install("deployment", dep_name, wait_count: POD_READINESS_TIMEOUT, namespace: csv[:namespace])
          findings << {kind: "Deployment", name: dep_name, namespace: csv[:namespace], reason: "not ready after #{POD_READINESS_TIMEOUT}s"}
        end
      end
    end

    if findings.empty?
      result.passed("Operator is installed: 🐜")
    else
      findings.each do |f|
        result.add_impacted_resource(f[:kind], f[:name], f[:namespace], reason: f[:reason])
      end
      first = findings.first
      more = findings.size > 1 ? " (+#{findings.size - 1} more)" : ""
      result.failed("Operator is not installed: #{first[:kind]}/#{first[:name]} in #{first[:namespace]} #{first[:reason]}#{more}")
    end
  end
end

# Names of the Deployments an OLM ClusterServiceVersion install strategy creates.
def operator_deployments(csv_name : String, namespace : String) : Array(String)
  csv = KubectlClient::Get.resource("csv", csv_name, namespace)
  deployments = csv.dig?("spec", "install", "spec", "deployments")
  if deployments
    deployments.as_a.compact_map { |d| d.dig?("name").try(&.as_s) }
  else
    [] of String
  end
end
