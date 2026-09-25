# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../../modules/docker_client"
require "halite"
require "totem"
require "../../modules/k8s_netstat"
require "../../modules/kernel_introspection"
require "../../modules/k8s_kernel_introspection"
require "../utils/utils.cr"

desc "The CNF test suite checks to see if CNFs follows microservice principles"
category_task "microservice", ["reasonable_image_size", "reasonable_startup_time", "single_process_type", "service_discovery", "shared_database", "specialized_init_system", "sig_term_handled", "zombie_handled"]

STRACE_WAIT_BUFFER = 3

enum StraceAttachResult
  Attached
  NotPermitted
  NoSuchProcess
end

desc "To check if the CNF has multiple microservices that share a database"
scored_task "shared_database",
  deps: ["setup:install_cluster_tools"],
  emoji: "💾" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # todo loop through local resources and see if db match found
    db_match = Netstat::Mariadb.match

    if db_match[:found] == false
      result.na("[shared_database] No MariaDB containers were found")
      next
    end

    resource_ymls = CNFManager.cnf_workload_resources(args, config) { |resource| resource }
    resource_names = Helm.workload_resource_kind_names(resource_ymls)
    helm_chart_cnf_services : Array(JSON::Any)
    helm_chart_cnf_services = resource_names.map do |resource_name|
      Log.info { "helm_chart_cnf_services resource_name: #{resource_name}"}
      if resource_name[:kind].downcase == "service"
        #todo check for namespace
        resource = KubectlClient::Get.resource(resource_name[:kind], resource_name[:name], resource_name[:namespace])
      end
      resource
    end.flatten.compact

    Log.info { "helm_chart_cnf_services: #{helm_chart_cnf_services}"}

    db_pod_ips = Netstat::K8s.get_all_db_pod_ips

    cnf_service_pod_ips = [] of Array(NamedTuple(service_group_id: Int32, pod_ips: Array(JSON::Any)))
    helm_chart_cnf_services.each_with_index do |helm_cnf_service, index|
      service_pods = KubectlClient::Get.pods_by_service(helm_cnf_service)
      if service_pods
        cnf_service_pod_ips << service_pods.map { |pod|
          {
            service_group_id: index,
            pod_ips: pod.dig("status", "podIPs").as_a.select{|ip|
              db_pod_ips.select{|dbip| dbip["ip"].as_s != ip["ip"].as_s}
            }
          }

        }.flatten.compact
      end
    end

    cnf_service_pod_ips = cnf_service_pod_ips.compact.flatten
    Log.info { "cnf_service_pod_ips: #{cnf_service_pod_ips}"}


    violators = Netstat::K8s.get_multiple_pods_connected_to_mariadb_violators

    Log.info { "violators: #{violators}"}
    Log.info { "cnf_service_pod_ips: #{cnf_service_pod_ips}"}


    cnf_violators = violators.find do |violator|
      cnf_service_pod_ips.find do |service|
        service["pod_ips"].find do |ip|
          violator["ip"].as_s.includes?(ip["ip"].as_s)
        end
      end
    end

    Log.info { "cnf_violators: #{cnf_violators}"}

    integrated_database_found = false

    if violators.size > 1 && cnf_violators
      result.append_description("Found multiple pod ips from different services that connect to the same database: #{violators}")
      integrated_database_found = true 
    end

    if integrated_database_found
      result.failed("Found a shared database (ভ_ভ) ރ")
    else
      result.passed("No shared database found 🖥️")
    end
  end
end

# Default limit for reasonable_startup_time; a CNF changes it with
# startup_time_max_seconds in the common section of cnti-testsuite.yaml.
REASONABLE_STARTUP_TIME_MAX_SECONDS = 30

# Seconds from the moment a pod's last container started running to the
# moment the pod reported Ready, read from the pod's status: image pulls and
# scheduling are excluded, the application's own start-up is what remains.
# Nil when the pod has no running container or never became Ready.
def pod_startup_seconds(pod : JSON::Any) : Float64?
  ready = (pod.dig?("status", "conditions").try(&.as_a?) || [] of JSON::Any).find { |c| c["type"]? == "Ready" && c["status"]? == "True" }
  ready_at = ready.try(&.dig?("lastTransitionTime")).try(&.as_s?)
  started = (pod.dig?("status", "containerStatuses").try(&.as_a?) || [] of JSON::Any).compact_map { |c| c.dig?("state", "running", "startedAt").try(&.as_s?) }
  return nil if ready_at.nil? || started.empty?
  started_at = started.map { |t| Time.parse_rfc3339(t) }.max
  seconds = (Time.parse_rfc3339(ready_at) - started_at).total_seconds
  seconds < 0 ? 0.0 : seconds
end

desc "Does the CNF have a reasonable startup time (#{REASONABLE_STARTUP_TIME_MAX_SECONDS} seconds unless startup_time_max_seconds is set)?"
scored_task "reasonable_startup_time" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # The start-up time is measured on the CNF's own pods, per workload
    # resource, as the slowest pod's time from container start to Ready.
    # The limit is a documented number, in the config, not a value fitted to
    # a disk benchmark (#2596).
    limit = config.common.startup_time_max_seconds || REASONABLE_STARTUP_TIME_MAX_SECONDS
    slow = 0
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      live = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      pods = KubectlClient::Get.pods_by_resource_labels(live, namespace: resource[:namespace])
      if pods.empty?
        result.append_description("#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: no pod to measure")
        next true
      end
      slowest = nil.as(Tuple(String, Float64)?)
      pods.each do |pod|
        name = pod.dig("metadata", "name").as_s
        seconds = pod_startup_seconds(pod)
        if seconds.nil?
          result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace], pod: name,
            reason: "never reported Ready (phase #{pod.dig?("status", "phase")})")
          slow += 1
          next
        end
        slowest = {name, seconds} if slowest.nil? || seconds > slowest[1]
      end
      next false if slowest.nil?
      pod_name, seconds = slowest
      result.append_description("#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: slowest pod #{pod_name} Ready #{seconds.round(1)} s after its containers started (limit #{limit} s)")
      if seconds > limit
        result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace], pod: pod_name,
          reason: "Ready #{seconds.round(1)} s after its containers started, over the #{limit} s limit")
        slow += 1
        false
      else
        true
      end
    end

    if task_response
      result.passed("CNF had a reasonable startup time 🚀")
    else
      result.append_remediation("Move work out of the start-up path (lazy initialisation, pre-built caches, smaller images), gate readiness on what the service needs rather than on a fixed initial delay, and use a startupProbe for genuinely slow starters.")
      result.failed("CNF had #{slow} workload(s) over the #{limit} s startup limit 🐢")
    end
  end
end

# Returns the maximum allowed compressed image size in bytes. The default is
# REASONABLE_IMAGE_SIZE_MAX_MB; only image_size_max_mb in the common section of
# cnti-testsuite.yaml changes it, so the verdict is reproducible from the
# config alone.
def reasonable_image_size_bytes(config) : Int64
  (config.common.image_size_max_mb || REASONABLE_IMAGE_SIZE_MAX_MB).to_i64 * 1_000_000
end

def image_size_in_mb(bytes : Int64) : String
  (bytes / 1_000_000.0).round(1).to_s
end

# Pulls fqdn_image into the dockerd pod and returns its gzipped size in bytes.
# Raises on any failure so callers can treat the image as unmeasurable. Every
# step is checked: Dockerd.exec does not raise on a failed command, and a
# leftover archive from the previous image would otherwise be measured in
# place of one that could not be pulled.
def docker_image_compressed_size(fqdn_image : String) : Int64
  Dockerd.exec!("rm -f /tmp/image.tar /tmp/image.tar.gz")
  Dockerd.exec!("docker pull #{fqdn_image}")
  Dockerd.exec!("docker save #{fqdn_image} -o /tmp/image.tar")
  Dockerd.exec!("gzip -f /tmp/image.tar")
  output = Dockerd.exec!("wc -c /tmp/image.tar.gz")[:output].to_s
  Dockerd.exec("rm -f /tmp/image.tar.gz")
  compressed_size = output.split.first?.try(&.to_i64?)
  raise "unexpected `wc -c` output: #{output.inspect}" unless compressed_size
  Log.info { "compressed_size: #{fqdn_image} = '#{compressed_size}'" }
  compressed_size
end

def docker_image_pull_auth(resource, image_secrets_config_path)
  image_pull_secrets = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace]).dig?("spec", "template", "spec", "imagePullSecrets")
  if image_pull_secrets
    auths = image_pull_secrets.as_a.map { |secret|
      Log.debug { "image pull secret: #{secret["name"]}" }
      secret_data = KubectlClient::Get.resource("Secret", "#{secret["name"]}", resource[:namespace]).dig?("data")
      if secret_data
        dockerconfigjson = Base64.decode_string("#{secret_data[".dockerconfigjson"]}")
        dockerconfigjson.gsub(%({"auths":{),"")[0..-3]
        # parsed_dockerconfigjson = JSON.parse(dockerconfigjson)
        # parsed_dockerconfigjson["auths"].to_json.gsub("{","").gsub("}", "")
      else
        # JSON.parse(%({}))
        ""
      end
    }
    if auths
      str_auths = %({"auths":{#{auths.reduce("") { | acc, x|
      acc + x.to_s + ","
    }[0..-2]}}})
      Log.debug { "constructed docker auths config for #{auths.size} secret(s)" }
    end
    File.write(image_secrets_config_path, str_auths)
    Dockerd.exec("mkdir -p /root/.docker/")
    KubectlClient::Utils.copy_to_pod("dockerd", image_secrets_config_path, "/root/.docker/config.json", namespace: TESTSUITE_NAMESPACE)
  end
end

def image_fqdn(image_url, image_registry_fqdns) : String
  image_url_parts = image_url.split("/")
  image_host = image_url_parts[0]

  # If FQDN mapping is available for the registry,
  # replace the host in the fqdn_image
  fqdn_image = image_url
  if !image_registry_fqdns.nil? && !image_registry_fqdns.empty?
    if image_registry_fqdns[image_host]?
      image_url_parts[0] = image_registry_fqdns[image_host]
      fqdn_image = image_url_parts.join("/")
    end
  end

  fqdn_image
end

desc "Are the CNF's container images under the size limit (#{REASONABLE_IMAGE_SIZE_MAX_MB} MB unless image_size_max_mb is set)?"
scored_task "reasonable_image_size",
  type: CNFManager::TestType::Bonus,
  emoji: "⚖👀" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    docker_insecure_registries = config.common.docker_insecure_registries || [] of String
    unless Dockerd.install(docker_insecure_registries)
      result.skipped("Skipping reasonable_image_size: Dockerd tool failed to install")
      next
    end

    max_size = reasonable_image_size_bytes(config)
    max_mb = max_size // 1_000_000
    Log.for(t.name).info { "max_size: #{max_size} (#{max_mb} MB)" }

    image_secrets_config_path = File.join(CNF_TEMP_FILES_DIR, "config.json")
    measured_images = {} of String => Bool
    oversized_images = [] of String
    inspected_targets = 0

    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _|

      # Only measure pod-styled containers; skip anything else without failing.
      unless WORKLOAD_RESOURCE_KIND_NAMES.includes?(resource[:kind].downcase) && container.as_h["image"]?
        next true
      end

      image_url = container.as_h["image"].as_s
      fqdn_image = image_fqdn(image_url, config.common.image_registry_fqdns)
      inspected_targets += 1

      # Reuse a previous measurement for duplicate images.
      if measured_images.has_key?(fqdn_image)
        next measured_images[fqdn_image]
      end

      # Registry auth may be required to pull the image.
      docker_image_pull_auth(resource, image_secrets_config_path)

      begin
        compressed_size = docker_image_compressed_size(fqdn_image)
      rescue ex
        Log.for(t.name).warn { "Could not measure #{fqdn_image}: #{ex.message}".colorize(:yellow) }
        next true
      end

      size_ok = compressed_size < max_size
      measured_images[fqdn_image] = size_ok

      size_mb = image_size_in_mb(compressed_size)
      if size_ok
        result.append_description("image #{fqdn_image} = #{size_mb} MB (limit #{max_mb} MB)")
        if compressed_size >= max_size * 4 // 5
          result.append_description("WARNING: image #{fqdn_image} is within 80% of the #{max_mb} MB limit")
        end
      else
        result.append_description("image #{fqdn_image} = #{size_mb} MB exceeds the #{max_mb} MB limit")
        oversized_images << fqdn_image
      end

      size_ok
    end

    if inspected_targets == 0 || measured_images.empty?
      result.skipped("Could not measure the size of any container image")
    elsif task_response && oversized_images.empty?
      result.passed("Image size is good 🐜")
    else
      result.failed("Image size too large 🦖: #{oversized_images.join(", ")}")
    end
  end
end

desc "Do the containers in a pod have only one process type?"
scored_task "single_process_type",
  type: CNFManager::TestType::Essential,
  emoji: "⚖👀" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    fail_msgs = Set(String).new
    ignored_init_msgs = Set(String).new
    checked_process_types = [] of String
    resources_checked = false
    test_passed = true

    CNFManager.cnf_workload_resources(args, config) do |resource|
      # Extract and convert necessary fields from the resource
      kind = resource["kind"].as_s?
      name = resource["metadata"]["name"].as_s?
      namespace = resource["metadata"]["namespace"].as_s?
      next unless kind && name && namespace

      # Create a NamedTuple with the necessary fields
      resource_named_tuple = {
        kind: kind,
        name: name,
        namespace: namespace
      }

      Log.info { "Constructed resource_named_tuple: #{resource_named_tuple}" }

      # Iterate over every container and verify there is only one application process type.
      ClusterTools.all_containers_by_resource?(resource_named_tuple, namespace, only_container_pids:true) do |container_id, container_pid_on_node, node, container_proctree_statuses, container_status|
        container_name = container_status["name"]?
        next if container_proctree_statuses.empty?
        resources_checked = true

        root_pid = container_pid_on_node.strip

        # The container's own init/supervisor process (PID 1, whose host pid ==
        # container_pid_on_node) is not an application process type, regardless of
        # which init binary it uses. A specialized init system (tini/dumb-init/s6) is
        # also excused wherever it appears in the tree, and when PID 1 is one, so is
        # the init's own supervision tree (s6-supervise and the other s6-* helpers).
        # Whatever remains is the set of application process types -- more than one
        # means the container runs multiple process types.
        root_is_specialized_init = container_proctree_statuses.any? do |status|
          status["Pid"].strip == root_pid && SPECIALIZED_INIT_SYSTEMS.includes?(status["Name"].strip)
        end
        app_process_types = container_proctree_statuses.reject do |status|
          process_name = status["Name"].strip
          status["Pid"].strip == root_pid ||
            SPECIALIZED_INIT_SYSTEMS.includes?(process_name) ||
            (root_is_specialized_init && InitSystems.init_system_process?(process_name))
        end.map { |status| status["Name"].strip }.uniq

        Log.for(t.name).info { "container '#{container_name}' application process types: #{app_process_types}" }
        if app_process_types.size <= 1
          checked_process_types << "#{kind}/#{name} container #{container_name}: #{app_process_types.empty? ? "no application process besides PID 1" : "process type #{app_process_types.first}"}"
        end

        # When the container's init process (PID 1) is a real init/supervisor that is
        # NOT one of the recommended specialized init systems, record that we saw it and
        # are deliberately not counting it against this test. Whether the init system is
        # a specialized one is scored separately by the specialized_init_system test.
        root_status = container_proctree_statuses.find { |status| status["Pid"].strip == root_pid }
        if root_status
          root_name = root_status["Name"].strip
          init_cmd = root_status["cmdline"]?.try do |cmd|
            cmd.split("\0").join(" ").gsub("\n", "\\n").strip
          end
          init_cmd = root_name if init_cmd.nil? || init_cmd.empty?
          if !SPECIALIZED_INIT_SYSTEMS.includes?(root_name) && app_process_types.any? { |ptype| ptype != root_name }
            ignored_init_msgs.add?(
              "Container `#{container_name}` in `#{kind}`: `#{name}` (namespace: `#{namespace}`) " \
              "uses non-specialized init system `#{init_cmd}` as its init process (PID 1). " \
              "This is not counted against single_process_type; whether the init system is a " \
              "recommended one is evaluated by the specialized_init_system test."
            )
          end
        end

        if app_process_types.size > 1
          proc_list = container_proctree_statuses.map do |proc|
            proc_name = proc["Name"]?
            proc_pid  = proc["Pid"]?
            proc_ppid = proc["PPid"]?
            proc_cmd = proc["cmdline"]?.try do |cmd|
              cmd.split("\0").join(" ").gsub("\n", "\\n").strip
            end || "N/A"
            "NAME=#{proc_name}, PID=#{proc_pid}, PPID=#{proc_ppid}, CMD=#{proc_cmd}"
          end.join("\n")

          result.add_impacted_resource(kind, name, namespace, container: container_name.to_s,
            reason: "#{app_process_types.size} process types: #{app_process_types.join(", ")}")
          fail_msg = "Container `#{container_name}` in `#{kind}`: `#{name}` (namespace: `#{namespace}`) has multiple process types.\n"
          fail_msg += "Running processes detected:\n"
          fail_msg += "#{proc_list}"

          fail_msgs.add?(fail_msg)
          test_passed = false
        end
      end
    end

    # Report every non-specialized init system that was found and ignored, so the
    # decision is visible in both stdout and the results file.
    ignored_init_msgs.each { |msg| result.append_description(msg) }

    if resources_checked
      if test_passed
        checked_process_types.each { |line| result.append_description(line) }
        result.passed("Only one process type used")
      else
        fail_msgs.each { |msg| result.append_description(msg) }
        result.failed("More than one process type used")
      end
    else
      result.skipped("Container resources not checked")
    end
  end
end


desc "Are the zombie processes handled?"
scored_task "zombie_handled",
  type: CNFManager::TestType::Essential,
  emoji: "⚖👀" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    injection_failures = [] of String
    probed_containers = [] of String
    # A probe needs a running container to enter. The test before this one,
    # sig_term_handled, terminates the CNF's PID 1 and the pod restarts; an
    # enumeration that finds no container at all is retried for the readiness
    # budget rather than taken as an answer (#2576). Nothing is probed twice:
    # the retry only happens while both lists are still empty.
    repeat_with_timeout(timeout: POD_READINESS_TIMEOUT, errormsg: "No running container of the CNF could be found to probe", delay: 5) do
      CNFManager.resource_refs(args, config, WORKLOAD_RESOURCE_KIND_NAMES) do |resource|
        ClusterTools.all_containers_by_resource?(resource, resource[:namespace], include_proctree: false) do |container_id, container_pid_on_node, node|
          # The probe runs from cluster-tools' own filesystem inside the container's PID
          # namespace, so nothing is written into the container: a read-only root
          # filesystem or a distroless image is probed like any other. /zombie forks a
          # child that execs /sleep and exits at once, so the child is orphaned onto the
          # container's PID 1 - the process under test - and is found later by its PPid.
          probe_command = "nsenter --target #{container_pid_on_node} --pid -- /zombie"
          cmd_result = ClusterTools.exec_by_node(probe_command, node)
          if cmd_result[:status].success?
            probed_containers << "#{resource[:kind]}/#{resource[:name]} container #{container_id.to_s[0, 12]}"
          else
            Log.for(t.name).error { "zombie probe could not be started in container #{container_id} (#{resource[:kind]}/#{resource[:name]}): #{probe_command}: #{cmd_result[:error]}" }
            injection_failures << "#{resource[:kind]}/#{resource[:name]} container #{container_id}: `#{probe_command}` failed"
          end
        end
      end
      !(probed_containers.empty? && injection_failures.empty?)
    end

    unless injection_failures.empty?
      injection_failures.each { |failure| result.append_description(failure) }
      result.skipped("Zombie reaping not checked: the zombie probe could not be started in every container")
      next
    end

    # The guard above covers a probe that was attempted and failed. This one
    # covers the case where nothing could be attempted: a verdict needs at
    # least one probed container, so an empty list is never a pass.
    if probed_containers.empty?
      result.skipped("Zombie reaping not checked: no running container of the CNF could be probed")
      next
    end

    sleep(Time::Span.new(seconds: 10))

    pods_to_restart = Set(Tuple(String, String)).new
    containers_to_restart = Set(Tuple(String, JSON::Any)).new
    task_response = CNFManager.workload_resource_test(args, config, check_containers:false ) do |resource, _, _|
      ClusterTools.all_containers_by_resource?(resource, resource[:namespace], only_container_pids: true, include_zombies: true) do | container_id, container_pid_on_node, node, container_proctree_statuses, container_status, pod_name| 

        zombies = container_proctree_statuses.map do |status|
          Log.for(t.name).debug { "status: #{status}" }
          Log.for(t.name).info { "status cmdline: #{status["cmdline"]}" }
          status_name = status["Name"].strip
          current_pid = status["Pid"].strip
          state = status["State"].strip
          Log.for(t.name).info { "pid: #{current_pid}" }
          Log.for(t.name).info { "status name: #{status_name}" }
          Log.for(t.name).info { "state: #{state}" }
          Log.for(t.name).info { "(state =~ /zombie/): #{(state =~ /zombie/)}" }
          if (state =~ /zombie/) != nil
            parent_pid = status["PPid"]?.try(&.strip)
            result.add_impacted_resource("Pod", pod_name.as_s, resource[:namespace], container: container_status["name"].as_s,
              reason: "process #{status_name} (pid #{current_pid}, parent #{parent_pid}) is a zombie: state #{state}")
            containers_to_restart << {container_id, node}
            pods_to_restart << {pod_name.as_s, resource[:namespace]}
            true
          else 
            nil
          end
        end
        Log.for(t.name).info { "zombies.all?(nil): #{zombies.all?(nil)}" }
        zombies.all?(nil)
      end
    end

    containers_to_restart.each do |container_id, node|
      Log.for(t.name).info { "Shutting down container #{container_id}" }
      ClusterTools.exec_by_node("ctr -n=k8s.io task kill --signal 9 #{container_id}", node)
    end

    if !pods_to_restart.empty?
      sleep(Time::Span.new(seconds: 20))
    end

    pods_to_restart.each do |pod_name, namespace|
      Log.for(t.name).info { "Waiting for pod #{pod_name} in namespace #{namespace} to become Ready..." }
      KubectlClient::Wait.wait_for_resource_availability("pod", pod_name, namespace, GENERIC_OPERATION_TIMEOUT)
    end

    if task_response
      result.append_description("Zombie probe started in #{probed_containers.size} container(s): #{probed_containers.join("; ")}")
      result.passed("Zombie handled")
    else
      result.failed("Zombie not handled")
    end
  end
end

# Attach strace to a PID in background, following all threads
def attach_strace(pid : String, node : JSON::Any)
  main_log_path = "/tmp/#{pid}-strace.#{pid}"

  # Start strace in background for all threads
  # Using timeout here is a small hack to avoid endless strace execution on unexpected failures
  cmd = "timeout #{GENERIC_OPERATION_TIMEOUT}s strace -ff -p #{pid} -o /tmp/#{pid}-strace"
  ClusterTools.exec_by_node_bg(cmd, node)

  # Ensure strace logging begins
  unless repeat_with_timeout(10, "Waiting for strace log file for PID #{pid} timed out", delay: 1) do
    result = ClusterTools.exec_by_node("ls /tmp | grep #{pid}-strace.#{pid} || true", node)
    !result[:output].strip.empty?
  end
    return StraceAttachResult::NoSuchProcess
  end

  # Read only the main process log
  contents = ClusterTools.exec_by_node("cat #{main_log_path} || true", node)[:output]
  return StraceAttachResult::NoSuchProcess if contents.empty? ||
                                              contents.includes?("No such process") ||
                                              contents.includes?("ptrace(PTRACE_SEIZE)")
  return StraceAttachResult::NotPermitted if contents.includes?("Operation not permitted")

  StraceAttachResult::Attached
end

# Waits up to `seconds` for every pid in `pids` to terminate on `node`, polling
# once a second, and returns the pids still alive when the window closes. A
# zombie has terminated: it only awaits its parent's wait(), which is the
# zombie_handled test's concern, not this one's.
def wait_for_processes_to_exit(pids : Array(String), node : JSON::Any, seconds : Int32) : Array(String)
  survivors = pids
  started = Time.utc
  loop do
    # No quotes inside: the probe travels through a local shell and kubectl exec.
    probe = survivors.map { |p| "s=$(grep -m1 ^State: /proc/#{p}/status 2>/dev/null | cut -f2 | cut -c1); [ -n \"$s\" ] && [ \"$s\" != Z ] && echo #{p}" }.join("; ")
    output = ClusterTools.exec_by_node("sh -c '#{probe}; true'", node)[:output]
    survivors = output.split("\n").map(&.strip).reject(&.empty?)
    break if survivors.empty? || Time.utc - started >= seconds.seconds
    sleep 1.second
  end
  survivors
end

# Check if SIGTERM appears in all strace log files
def check_sigterm_in_strace_logs(pid : String, node : JSON::Any) : Bool
  # List all thread log files for this PID on the remote node
  result = ClusterTools.exec_by_node("ls /tmp | grep #{pid}-strace || true", node)
  files = result[:output].split("\n").reject(&.empty?).map { |f| "/tmp/#{f}" }

  if files.empty?
    Log.warn { "No strace log files found for PID #{pid} on node." }
    return false
  end

  begin
    files.each do |file|
      contents = ClusterTools.exec_by_node("cat #{file} || true", node)[:output]
      next if contents.empty?

      if contents.includes?("SIGTERM")
        Log.info { "SIGTERM found in #{file}" }
        return true
      end
    end
    false
  ensure
    ClusterTools.exec_by_node("rm -f /tmp/#{pid}-strace*", node)
  end
end

desc "Are the SIGTERM signals handled?"
scored_task "sig_term_handled",
  type: CNFManager::TestType::Essential,
  emoji: "⚖👀" do |t, args|
  logger = ::Log.for(t.name)

  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # We'll store any failures (or skips) in this array:
    failed_containers = [] of NamedTuple(
      namespace: String,
      pod: String,
      container: String,
      test_status: String,
      test_reason: String | Nil
    )

    # Containers that could not be judged, with the reason; they never count
    # against the CNF.
    skipped_containers = [] of NamedTuple(pod: String, container: String, reason: String)
    checked_containers = [] of String
    judged_any = false

    #Track already tested pods
    tested_pods = Set(String).new

    # Iterate over all resources
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, container, _|
      kind = resource["kind"].downcase

      # Early skip if this is not a relevant workload resource
      next true unless kind.in?(["deployment","statefulset","pod","replicaset","daemonset"])

      resource_yaml = nil
      begin
        resource_yaml = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      rescue ex: KubectlClient::ShellCMD::NotFoundError
        logger.error { "Failed to retrieve resource #{resource[:kind]}/#{resource[:name]}: #{ex.message}" }
        next false
      end

      pods = [] of JSON::Any
      begin
        pods = KubectlClient::Get.pods_by_resource_labels(resource_yaml, resource[:namespace])
      rescue ex: KubectlClient::ShellCMD::NotFoundError
        logger.error { "Failed to retrieve pods for #{resource[:kind]}/#{resource[:name]}: #{ex.message}" }
        next false
      end

      # Every pod and every container is judged and reported; the verdicts are
      # combined afterwards, so one run shows the whole picture.
      pods.map do |pod|
        pod_name      = pod.dig("metadata", "name").as_s
        pod_namespace = pod.dig("metadata", "namespace").as_s

        # Skip already tested pods
        pod_unique_id = "#{pod_namespace}/#{pod_name}"
        if tested_pods.includes?(pod_unique_id)
          logger.info { "Skipping already tested pod: #{pod_unique_id}" }
          next true
        end

        KubectlClient::Wait.wait_for_resource_availability("pod", pod_name, pod_namespace, GENERIC_OPERATION_TIMEOUT)

        status = pod["status"]
        next true unless status["containerStatuses"]?

        # The window a process gets to act on SIGTERM is the one the kubelet
        # would give it: the pod's grace period.
        grace_seconds = pod.dig?("spec", "terminationGracePeriodSeconds").try(&.as_i) || 30
        grace_seconds = {grace_seconds, GENERIC_OPERATION_TIMEOUT}.min

        pod_passed = status["containerStatuses"].as_a.map do |c_stat|
          c_name = c_stat["name"].as_s
          skip = ->(reason : String) do
            logger.info { "Skipping #{pod_name}/#{c_name}: #{reason}" }
            skipped_containers << {pod: pod_name, container: c_name, reason: reason}
            true
          end

          next skip.call("container not ready") unless c_stat["ready"].as_bool

          # Find the container's host PID
          c_id = c_stat["containerID"].as_s
          node = KubectlClient::Get.nodes_by_pod(pod).first
          pid  = ClusterTools.node_pid_by_container_id(c_id, node)
          next skip.call("no node PID found for the container") if pid.nil? || pid.empty?

          # The container's processes, threads excluded (Tgid != Pid means a thread).
          pids           = KernelIntrospection::K8s::Node.pids(node)
          proc_statuses  = KernelIntrospection::K8s::Node.all_statuses_by_pids(pids, node)
          process_tree   = KernelIntrospection::K8s::Node.proctree_by_pid(pid, node, proc_statuses)
          non_threads = process_tree.select do |info|
            tgid = info["Tgid"].to_s.strip
            cpid = info["Pid"].to_s.strip
            tgid.empty? || (tgid == cpid)
          end

          # What is judged: a lone PID 1 is judged itself; a PID 1 with children
          # is a supervisor, and its children are judged instead - SIGTERM sent to
          # the supervisor must reach them and they must act on it.
          judged = non_threads.map { |info| info["Pid"].to_s.strip }
          supervised = judged.size > 1
          judged = judged.reject { |cpid| cpid == pid } if supervised
          next skip.call("no process to judge") if judged.empty?

          # strace is evidence, not the verdict: for a supervised child it shows
          # whether the signal was forwarded at all. A tracer that cannot attach
          # (ptrace restrictions) leaves the outcome check to decide alone.
          traced = [] of String
          judged.dup.each do |cpid|
            case attach_strace(cpid, node)
            when StraceAttachResult::Attached
              traced << cpid
            when StraceAttachResult::NotPermitted
              logger.info { "strace not permitted for PID #{cpid}; judging by outcome only." }
            when StraceAttachResult::NoSuchProcess
              logger.info { "Process #{cpid} is gone already; not judged." }
              judged.delete(cpid)
            end
          end
          next skip.call("no process to judge") if judged.empty?
          sleep(Time::Span.new(seconds: STRACE_WAIT_BUFFER)) unless traced.empty?

          judged_any = true
          checked_containers << "#{pod_name}/#{c_name}: PID 1 #{pid}#{supervised ? " (supervisor)" : ""}, judged pid(s) #{judged.join(", ")}, grace #{grace_seconds}s"
          ClusterTools.exec_by_node("kill -TERM #{pid} || true", node)
          survivors = wait_for_processes_to_exit(judged, node, grace_seconds)
          # Whatever is still alive did not act on SIGTERM; end it the way the
          # kubelet would, so the pod can restart and the next test starts clean.
          ClusterTools.exec_by_node("kill -9 #{pid} || true", node) unless survivors.empty? && !supervised
          sleep(Time::Span.new(seconds: STRACE_WAIT_BUFFER)) unless traced.empty?
          # PID 1 is gone, so kubelet restarts the container. Give the pod the
          # readiness budget to come back before moving on: the next test
          # (zombie_handled) needs a running container to probe (#2576).
          KubectlClient::Wait.wait_for_resource_availability("pod", pod_name, pod_namespace, POD_READINESS_TIMEOUT)

          not_delivered = traced.reject { |cpid| check_sigterm_in_strace_logs(cpid, node) }
          logger.info { "#{pod_name}/#{c_name}: judged #{judged}, survivors after #{grace_seconds}s: #{survivors}, never received SIGTERM: #{not_delivered}" }

          if survivors.empty? && not_delivered.empty?
            true
          else
            reason = [] of String
            reason << "still running #{grace_seconds}s after SIGTERM: #{survivors.join(", ")}" unless survivors.empty?
            reason << "never received SIGTERM (not forwarded by PID 1): #{not_delivered.join(", ")}" unless not_delivered.empty?
            failed_containers << {
              namespace: pod_namespace,
              pod: pod_name,
              container: c_name,
              test_status: "failed",
              test_reason: reason.join("; ")
            }
            false
          end
        end.all?

        #put tested pod ID into checking list
        tested_pods << pod_unique_id

        #return bool
        pod_passed
      end.all?
    end

    skipped_containers.each do |info|
      result.append_description("Pod: #{info[:pod]}, Container: #{info[:container]}, Result: skipped, Reason: #{info[:reason]}")
    end

    if task_response && !judged_any
      result.skipped("Sig Term handling not checked: no container could be traced")
    elsif task_response
      checked_containers.each { |line| result.append_description("Checked #{line}") }
      result.passed("Sig Term handled")
    else
      failed_containers.each do |info|
        result.add_impacted_resource("Pod", info[:pod], info[:namespace], container: info[:container], reason: info[:test_reason].to_s)
      end
      result.failed("Sig Term not handled")
    end
  end
end

desc "Is every workload resource of the CNF exposed by a Service?"
scored_task "service_discovery",
  type: CNFManager::TestType::Bonus,
  emoji: "⚖👀" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # The CNF's Services with their live selectors. Judged per workload
    # resource against its pod template labels, so the verdict names each
    # workload nothing exposes instead of passing on the first match (#2593).
    services = [] of NamedTuple(name: String, namespace: String, selector: Hash(String, JSON::Any))
    CNFManager.resource_refs(args, config, ["service"]) do |service|
      selector = KubectlClient::Get.resource("service", service[:name], service[:namespace]).dig?("spec", "selector").try(&.as_h?)
      # A Service without a selector (an ExternalName or a manually endpointed one) exposes no pod by label.
      services << {name: service[:name], namespace: service[:namespace], selector: selector} if selector && !selector.empty?
    rescue KubectlClient::ShellCMD::NotFoundError
      Log.for(t.name).warn { "Service #{service[:name]} in #{service[:namespace]} is in the manifest but not in the cluster" }
    end

    unexposed = 0
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      live = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      labels = (live.dig?("spec", "template", "metadata", "labels") || live.dig?("metadata", "labels")).try(&.as_h?) || {} of String => JSON::Any
      exposing = services.select do |service|
        service[:namespace] == resource[:namespace] &&
          service[:selector].all? { |key, value| labels[key]? == value }
      end
      if exposing.empty?
        result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace], reason: "no Service of the CNF selects its pods")
        unexposed += 1
        false
      else
        result.append_description("#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: exposed by Service #{exposing.map(&.[:name]).join(", ")}")
        true
      end
    end

    if task_response
      result.passed("Every workload resource of the CNF is exposed by a Service")
    else
      result.append_remediation("Expose each workload through a Service whose selector matches its pod labels; a workload that is reached only through the host network or a secondary interface can declare that as a documented exception.")
      result.failed("#{unexposed} workload resource(s) of the CNF are not exposed by a Service")
    end
  end
end

desc "To check if the CNF uses a specialized init system"
scored_task "specialized_init_system",
  type: CNFManager::TestType::Essential,
  deps: ["setup:install_cluster_tools"],
  emoji: "🚀" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    error_occurred    = false
    resources_checked = false
    checked_inits     = [] of String

    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      Log.for(t.name).info { "Checking #{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}" }

      # Try to list pods for this resource; on error => mark skip
      yaml = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      pods = begin
        KubectlClient::Get.pods_by_resource_labels(yaml, resource[:namespace])
      rescue ex
        result.append_description("Could not list pods for #{resource[:kind]}/#{resource[:name]}: #{ex.message}")
        error_occurred = true
        next false
      end

      resources_checked = true

      # Every pod is inspected and reported; the verdict comes afterwards.
      pods.map do |pod|
        pod_name = pod.dig("metadata", "name").as_s
        Log.for(t.name).info { "Inspecting pod #{pod_name}" }

        results = InitSystems.scan(pod)

        # Scan error => skip this resource
        if results.nil?
          result.append_description("Error scanning init system in pod #{pod_name}")
          error_occurred = true
          next false
        end

        results.select(&.specialized).each do |info|
          checked_inits << "#{info.kind}/#{info.name} container #{info.container}: init '#{info.init_cmd}'"
        end
        failed = results.reject(&.specialized)

        # No failures => this pod passes
        if failed.empty?
          next true
        end

        # Report failures
        failed.each do |info|
          result.add_impacted_resource(info.kind.to_s, info.name.to_s, info.namespace.to_s, container: info.container.to_s, reason: "'#{info.init_cmd}' as init process")
        end

        # mark this resource as failing
        next false
      end.all?(true)
    end

    if error_occurred
      result.skipped("An error occurred during container inspection")
    elsif !resources_checked
      result.skipped("Container checks not executed")
    elsif !task_response
      result.failed("Containers do not use specialized init systems (ভ_ভ) ރ")
    else
      checked_inits.each { |line| result.append_description(line) }
      result.passed("Containers use specialized init systems 🖥️")
    end
  end
end
