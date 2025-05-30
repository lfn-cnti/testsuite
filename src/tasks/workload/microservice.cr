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
task "microservice", ["reasonable_image_size", "reasonable_startup_time", "single_process_type", "service_discovery", "shared_database", "specialized_init_system", "sig_term_handled"] do |_, args|
  stdout_score("microservice")
  case "#{ARGV.join(" ")}" 
  when /microservice/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end

REASONABLE_STARTUP_BUFFER = 10.0
STRACE_WAIT_BUFFER = 3.0

enum StraceAttachResult
  Attached
  NotPermitted
  NoSuchProcess
end

desc "To check if the CNF has multiple microservices that share a database"
task "shared_database", ["setup:install_cluster_tools"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    # todo loop through local resources and see if db match found
    db_match = Netstat::Mariadb.match

    if db_match[:found] == false
      next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::NA, "[shared_database] No MariaDB containers were found")
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
      puts "Found multiple pod ips from different services that connect to the same database: #{violators}".colorize(:red)
      integrated_database_found = true 
    end

    if integrated_database_found
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Found a shared database (ভ_ভ) ރ")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "No shared database found 🖥️")
    end
  end
end

desc "Does the CNF have a reasonable startup time (< 30 seconds)?"
task "reasonable_startup_time" do |t, args|
  # TODO (kosstennbl) Redesign this test, now it is based only on livness probes. 
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    current_dir = FileUtils.pwd
    helm = Helm::BinarySingleton.helm
    Log.debug {helm}

    # (kosstennbl) That part was copied from cnf_manager.cr, but it wasn't given much attention as
    # it would be probably redesigned in future.
    startup_time = 0
    resource_ymls = CNFManager.cnf_workload_resources(args, config) { |resource| resource }
    # get liveness probe initialDelaySeconds and FailureThreshold
    # if   ((periodSeconds * failureThreshhold) + initialDelaySeconds) / defaultFailureThreshold) > startuptimelimit then fail; else pass
    # get largest startuptime of all resoures
    resource_ymls.map do |resource|
      kind = resource["kind"].as_s.downcase
      case kind 
      when "pod"
        Log.for(t.name).info { "resource: #{resource}" }
        containers = resource.dig("spec", "containers")
      when .in?(WORKLOAD_RESOURCE_KIND_NAMES)
        Log.for(t.name).info { "resource: #{resource}" }
        containers = resource.dig("spec", "template", "spec", "containers")
      end
      containers && containers.as_a.map do |container|
        initialDelaySeconds = container.dig?("livenessProbe", "initialDelaySeconds")
        failureThreshhold = container.dig?("livenessProbe", "failureThreshhold")
        periodSeconds = container.dig?("livenessProbe", "periodSeconds")
        total_period_failure = 0 
        total_extended_period = 0
        adjusted_with_default = 0
        defaultFailureThreshold = 3
        defaultPeriodSeconds = 10

        if !failureThreshhold.nil? && failureThreshhold.as_i?
          ft = failureThreshhold.as_i
        else
          ft = defaultFailureThreshold
        end

        if !periodSeconds.nil? && periodSeconds.as_i?
          ps = periodSeconds.as_i
        else
          ps = defaultPeriodSeconds
        end

        total_period_failure = ps * ft

        if !initialDelaySeconds.nil? && initialDelaySeconds.as_i?
          total_extended_period = initialDelaySeconds.as_i + total_period_failure
        else
          total_extended_period = total_period_failure
        end

        adjusted_with_default = (total_extended_period / defaultFailureThreshold).round.to_i

        Log.info { "total_period_failure: #{total_period_failure}" }
        Log.info { "total_extended_period: #{total_extended_period}" }
        Log.info { "startup_time: #{startup_time}" }
        Log.info { "adjusted_with_default: #{adjusted_with_default}" }
        if startup_time < adjusted_with_default
          startup_time = adjusted_with_default
        end
      end
    end
    # Correlation for a slow box vs a fast box 
    # sysbench base fast machine (disk), time in ms 0.16
    # sysbench base slow machine (disk), time in ms 6.55
    # percentage 0.16 is 2.44% of 6.55
    # How much more is 6.55 than 0.16? (0.16 - 6.55) / 0.16 * 100 = 3993.75%
    # startup time fast machine: 21 seconds
    # startup slow machine: 34 seconds
    # how much more is 34 seconds than 21 seconds? (21 - 34) / 21 * 100 = 61.90%
    # app seconds set 1: 21, set 2: 34
    # disk miliseconds set 1: .16 set 2: 6.55
    # get the mean of app seconds (x)
    #   (sum all: 55, count number of sets: 2, divide sum by count: 27.5)
    # get the mean of disk milliseconds (y)
    #   (sum all: 6.71, count number of sets: 2, divide sum by count: 3.35)
    # Subtract the mean of x from every x value (call them "a")
    # set 1: 6.5 
    # set 2: -6.5 
    # and subtract the mean of y from every y value (call them "b")
    # set 1: 3.19
    # set 2: -3.2
    # calculate: ab, a2 and b2 for every value
    # set 1: 20.735, 42.25, 42.25
    # set 2: 20.8, 10.17, 10.24
    # Sum up ab, sum up a2 and sum up b2
    # 41.535, 52.42, 52.49
    # Divide the sum of ab by the square root of [(sum of a2) × (sum of b2)]
    # (sum of a2) × (sum of b2) = 2751.5258
    # square root of 2751.5258 = 52.4549
    # divide sum of ab by sqrt = 41.535 / 52.4549 = .7918
    # example
    # sysbench returns a 5.55 disk millisecond result
    # disk millisecond has a pearson correlation of .79 to app seconds
    # 
    # Regression for predication based on slow and fast box disk times
    # regression = ŷ = bX + a
    # b = 2.02641
    # a = 20.72663

    resp = K8sInstrumentation.disk_speed
    if resp["95th percentile"]?
        disk_speed = resp["95th percentile"].to_f
      startup_time_limit = ((0.30593 * disk_speed) + 21.9162 + REASONABLE_STARTUP_BUFFER).round.to_i
    else
      startup_time_limit = 30
    end
    # if ENV["CRYSTAL_ENV"]? == "TEST"
    #   startup_time_limit = 35 
    #   Log.info { "startup_time_limit TEST mode: #{startup_time_limit}" }
    # end
    Log.info { "startup_time_limit: #{startup_time_limit}" }
    Log.info { "startup_time: #{startup_time}" }

    if startup_time <= startup_time_limit
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "CNF had a reasonable startup time 🚀")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF had a startup time of #{startup_time} seconds 🐢")
    end
  end
end

# There aren't any 5gb images to test.
# To run this test in a test environment or for testing purposes,
# set the env var CRYSTAL_ENV=TEST when running the test.
#
# Example:
#    CRYSTAL_ENV=TEST ./cnf-testsuite reasonable_image_size
#
desc "Does the CNF have a reasonable container image size (< 5GB)?"
task "reasonable_image_size" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args,config|
    docker_insecure_registries = config.common.docker_insecure_registries || [] of String
    unless Dockerd.install(docker_insecure_registries)
      next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Skipping reasonable_image_size: Dockerd tool failed to install")
    end

    Log.for(t.name).debug { "cnf_config: #{config}" }
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|

      image_secrets_config_path = File.join(CNF_TEMP_FILES_DIR, "config.json")

      if resource["kind"].downcase == "deployment" ||
          resource["kind"].downcase == "statefulset" ||
          resource["kind"].downcase == "pod" ||
          resource["kind"].downcase == "replicaset"
          test_passed = true

        image_url = container.as_h["image"].as_s
        image_url_parts = image_url.split("/")
        image_host = image_url_parts[0]

        # Set default FQDN value
        fqdn_image = image_url

        # If FQDN mapping is available for the registry,
        # replace the host in the fqdn_image
        image_registry_fqdns = config.common.image_registry_fqdns
        if !image_registry_fqdns.nil? && !image_registry_fqdns.empty?
          image_registry_fqdns = image_registry_fqdns.not_nil!
          if image_registry_fqdns[image_host]?
            image_url_parts[0] = image_registry_fqdns[image_host]
            fqdn_image = image_url_parts.join("/")
          end
        end

        image_pull_secrets = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace]).dig?("spec", "template", "spec", "imagePullSecrets")
        if image_pull_secrets
          auths = image_pull_secrets.as_a.map { |secret|
            puts secret["name"]
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
            puts "str_auths: #{str_auths}"
          end
          File.write(image_secrets_config_path, str_auths)
          Dockerd.exec("mkdir -p /root/.docker/")
          KubectlClient::Utils.copy_to_pod("dockerd", image_secrets_config_path, "/root/.docker/config.json", namespace: TESTSUITE_NAMESPACE)
        end

        Log.info { "FQDN of the docker image: #{fqdn_image}" }
        Dockerd.exec("docker pull #{fqdn_image}")
        Dockerd.exec("docker save #{fqdn_image} -o /tmp/image.tar")
        Dockerd.exec("gzip -f /tmp/image.tar")
        exec_resp = Dockerd.exec("wc -c /tmp/image.tar.gz | awk '{print$1}'")
        compressed_size = exec_resp[:output]
        # TODO strip out secret from under auths, save in array
        # TODO make a new auths array, assign previous array into auths array
        # TODO save auths array to a file
        Log.info { "compressed_size: #{fqdn_image} = '#{compressed_size.to_s}'" }
        max_size = 5_000_000_000
        if ENV["CRYSTAL_ENV"]? == "TEST"
           Log.info { "Using Test Mode max_size" }
           max_size = 16_000_000
        end

        begin
          unless compressed_size.to_s.to_i64 < max_size
            puts "resource: #{resource} and container: #{fqdn_image} was more than #{max_size}".colorize(:red)
            test_passed=false
          end
        rescue ex
          Log.for(t.name).error { "invalid compressed_size: #{fqdn_image} = '#{compressed_size.to_s}', #{ex.message}".colorize(:red) }
          test_passed = false
        end
      else
        test_passed = true
      end
      test_passed
    end

    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Image size is good 🐜")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Image size too large 🦖")
    end
  end
end

desc "Do the containers in a pod have only one process type?"
task "process_search" do |_, args|
  pod_info = KernelIntrospection::K8s.find_first_process("sleep 30000")
  puts "pod_info: #{pod_info}"
  proctree = KernelIntrospection::K8s::Node.proctree_by_pid(pod_info[:pid], pod_info[:node]) if pod_info
  puts "proctree: #{proctree}"

end

desc "Do the containers in a pod have only one process type?"
task "single_process_type" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    fail_msgs = [] of String
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

      # Iterate over every container and verify there is only one process type
      ClusterTools.all_containers_by_resource?(resource_named_tuple, namespace, only_container_pids:true) do |container_id, container_pid_on_node, node, container_proctree_statuses, container_status|
        previous_process_type = "initial_name"

        container_proctree_statuses.each do |status|
          status_name = status["Name"].strip
          ppid = status["PPid"].strip
          Log.for(t.name).info { "status name: #{status_name}" }
          Log.for(t.name).info { "previous status name: #{previous_process_type}" }
          resources_checked = true

          if status_name != previous_process_type && previous_process_type != "initial_name"
            verified = KernelIntrospection::K8s::Node.verify_single_proc_tree(ppid, status_name, container_proctree_statuses, SPECIALIZED_INIT_SYSTEMS)
            unless verified
              Log.for(t.name).info { "multiple proc types detected verified: #{verified}" }
              fail_msg = "resource: #{resource} has more than one process type (#{container_proctree_statuses.map { |x| x["cmdline"]? }.compact.uniq.join(", ")})"
              unless fail_msgs.find { |x| x == fail_msg }
                puts fail_msg.colorize(:red)
                fail_msgs << fail_msg
              end
              test_passed = false
            end
          end

          previous_process_type = status_name
        end
      end
    end

    if resources_checked
      if test_passed
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Only one process type used")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "More than one process type used")
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Container resources not checked")
    end
  end
end


desc "Are the zombie processes handled?"
task "zombie_handled" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args,config|
    task_response = CNFManager.workload_resource_test(args, config, check_containers:false ) do |resource, container, initialized|
            ClusterTools.all_containers_by_resource?(resource, resource[:namespace], include_proctree: false) do | container_id, container_pid_on_node, node| 
        ClusterTools.exec_by_node("nerdctl --namespace=k8s.io cp /zombie #{container_id}:/zombie", node)
        ClusterTools.exec_by_node("nerdctl --namespace=k8s.io cp /sleep #{container_id}:/sleep", node)
        ClusterTools.exec_by_node("nerdctl --namespace=k8s.io exec #{container_id} /zombie", node)
      end
    end

    sleep 10.0

    pods_to_restart = Set(Tuple(String, String)).new
    containers_to_restart = Set(Tuple(String, JSON::Any)).new
    task_response = CNFManager.workload_resource_test(args, config, check_containers:false ) do |resource, container, initialized|
      ClusterTools.all_containers_by_resource?(resource, resource[:namespace], only_container_pids:true) do | container_id, container_pid_on_node, node, container_proctree_statuses, container_status, pod_name| 

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
            puts "Process #{status_name} in container #{container_id} of pod #{pod_name.as_s} has a state of #{state}".colorize(:red)
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
      sleep 20.0
    end

    pods_to_restart.each do |pod_name, namespace|
      Log.for(t.name).info { "Waiting for pod #{pod_name} in namespace #{namespace} to become Ready..." }
      KubectlClient::Wait.wait_for_resource_availability("pod", pod_name, namespace, GENERIC_OPERATION_TIMEOUT)
    end

    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Zombie handled")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Zombie not handled")
    end
  end
end

# Attach strace to a PID in background
def attach_strace(pid : String, node : JSON::Any)
  path = "/tmp/#{pid}-strace"

  # Using timeout here is a small hack to avoid endless strace execution on unexpected failures
  cmd = "timeout #{GENERIC_OPERATION_TIMEOUT}s strace -p #{pid} -e 'trace=!all' 2>&1 | tee #{path}"
  ClusterTools.exec_by_node_bg(cmd, node)

  # Ensure strace logging begins
  unless repeat_with_timeout(10, "Waiting for strace log file #{path} timed out", delay: 1) { File.exists?(path) }
    return StraceAttachResult::NoSuchProcess
  end

  contents = File.read(path)
  return StraceAttachResult::NoSuchProcess if contents.empty? ||
                                              contents.includes?("No such process") ||
                                              contents.includes?("ptrace(PTRACE_SEIZE)")
  return StraceAttachResult::NotPermitted  if contents.includes?("Operation not permitted")

  StraceAttachResult::Attached
end

# Checks if SIGTERM appears in the PID's strace log
def check_sigterm_in_strace_logs(pid : String) : Bool
  path = "/tmp/#{pid}-strace"
  return false unless File.exists?(path)
  File.read(path).includes?("SIGTERM")
end

desc "Are the SIGTERM signals handled?"
task "sig_term_handled" do |t, args|
  logger = ::Log.for(t.name)

  CNFManager::Task.task_runner(args, task: t) do |args, config|
    # We'll store any failures (or skips) in this array:
    failed_containers = [] of NamedTuple(
      namespace: String,
      pod: String,
      container: String,
      test_status: String,
      test_reason: String | Nil
    )

    # Iterate over all resources
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, container, initialized|
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

      # For each pod, do the main SIGTERM check
      pods.all? do |pod|
        pod_name      = pod.dig("metadata", "name").as_s
        pod_namespace = pod.dig("metadata", "namespace").as_s
        KubectlClient::Wait.wait_for_resource_availability("pod", pod_name, pod_namespace, GENERIC_OPERATION_TIMEOUT)

        status = pod["status"]
        next true unless status["containerStatuses"]?

        container_statuses = status["containerStatuses"].as_a
        container_statuses.all? do |c_stat|
          c_name = c_stat["name"].as_s
          ready  = c_stat["ready"].as_bool
          unless ready
            failed_containers << {
              namespace: pod_namespace,
              pod: pod_name,
              container: c_name,
              test_status: "skipped",
              test_reason: "Not ready"
            }
            next false
          end

          # Find the container's host PID
          c_id = c_stat["containerID"].as_s
          node = KubectlClient::Get.nodes_by_pod(pod).first
          pid  = ClusterTools.node_pid_by_container_id(c_id, node)

          if pid.nil? || pid.empty?
            failed_containers << {
              namespace: pod_namespace,
              pod: pod_name,
              container: c_name,
              test_status: "skipped",
              test_reason: "No Node PID found"
            }
            next false
          end

          # Child process check
          pids           = KernelIntrospection::K8s::Node.pids(node)
          proc_statuses  = KernelIntrospection::K8s::Node.all_statuses_by_pids(pids, node)
          process_tree   = KernelIntrospection::K8s::Node.proctree_by_pid(pid, node, proc_statuses)

          # Filter out threads (Tgid != Pid means it's a thread).
          non_threads = process_tree.select do |info|
            tgid = info["Tgid"].to_s.strip
            cpid = info["Pid"].to_s.strip
            tgid.empty? || (tgid == cpid)
          end

          # Attach strace to each non-thread process (besides the top if it has children)
          attached_pids = [] of String
          non_threads.each do |info|
            cpid = info["Pid"].to_s.strip

            # If the container has multiple processes, we want to verify that the SIGTERM signal sent to PID 1
            # is properly propagated to its child processes.
            if cpid == pid && non_threads.size > 1
              logger.info {"Skipping top PID #{cpid} (it has children)."}
              next
            end

            attach_result = attach_strace(cpid, node)
            case attach_result
            when StraceAttachResult::Attached
              attached_pids << cpid
            when StraceAttachResult::NotPermitted
              logger.info {"Skipping process #{cpid}; strace not permitted."}
            when StraceAttachResult::NoSuchProcess
              logger.info {"Skipping ephemeral/gone process #{cpid}."}
            end
          end

          logger.info {"Attached strace to PIDs: #{attached_pids.join(", ")}"}
          sleep STRACE_WAIT_BUFFER

          # Send SIGTERM => wait => SIGKILL
          ClusterTools.exec_by_node("bash -c 'kill -TERM #{pid} || true; sleep 5; kill -9 #{pid} || true'", node)
          sleep STRACE_WAIT_BUFFER

          # If no processes were attached, treat that as "skip"
          if attached_pids.empty?
            failed_containers << {
              namespace: pod_namespace,
              pod: pod_name,
              container: c_name,
              test_status: "skipped",
              test_reason: "No valid processes to trace."
            }
            next false
          end

          # Check each attached process's log for SIGTERM
          results = attached_pids.map do |p|
            found = check_sigterm_in_strace_logs(p)
            logger.info {"PID #{p} => SIGTERM captured? #{found}"}
            found
          end

          if results.all?(true)
            true
          else
            failed_containers << {
              namespace: pod_namespace,
              pod: pod_name,
              container: c_name,
              test_status: "failed",
              test_reason: "At least one process did not observe SIGTERM"
            }
            false
          end
        end
      end
    end

    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Sig Term handled")
    else
      # Otherwise, print out each container that failed or was skipped
      failed_containers.each do |info|
        msg = "Pod: #{info["pod"]}, Container: #{info["container"]}, Result: #{info["test_status"]}"
        msg += ", Reason: #{info["test_reason"]}" if info["test_status"] == "skipped"
        stdout_failure msg
      end
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Sig Term not handled")
    end
  end
end

desc "Are any of the containers exposed as a service?"
task "service_discovery" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args,config|
    # Get all resources for the CNF
    resource_ymls = CNFManager.cnf_workload_resources(args, config) { |resource| resource }
    resources = Helm.workload_resource_kind_names(resource_ymls)

    # Collect service names from the CNF resource list
    cnf_service_names = [] of String
    resources.each do |resource|
      case resource[:kind].downcase
      when "service"
        cnf_service_names.push(resource[:name])
      end
    end

    # Get all the pods in the cluster
    pods = KubectlClient::Get.resource("pods", all_namespaces: true).dig("items").as_a

    # Get pods for the services in the CNF based on the labels
    test_passed = false
    KubectlClient::Get.resource("services", all_namespaces: true).dig("items").as_a.each do |service_info|
      # Only check for pods for services that are defined by the CNF
      service_name = service_info["metadata"]["name"]
      next unless cnf_service_names.includes?(service_name)

      # Some services may not have selectors defined. Example: service/kubernetes
      pod_selector = service_info.dig?("spec", "selector")
      next unless pod_selector

      # Fetch matching pods for the CNF
      # If any service has a matching pod, then mark test as passed
      matching_pods = KubectlClient::Get.pods_by_labels(pods, pod_selector.as_h)
      if matching_pods.size > 0
        Log.debug { "Matching pods for service #{service_name}: #{matching_pods.inspect}" }
        test_passed = true
      end
    end

    if test_passed
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Some containers exposed as a service")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "No containers exposed as a service")
    end
  end
end

desc "To check if the CNF uses a specialized init system"
task "specialized_init_system", ["setup:install_cluster_tools"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    failed_cnf_resources = [] of InitSystems::InitSystemInfo
    resources_checked = false
    error_occurred = false
    CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      kind = resource["kind"].downcase
      case kind 
      when .in?(WORKLOAD_RESOURCE_KIND_NAMES)
        namespace = resource[:namespace]
        Log.for(t.name).info { "Checking resource #{resource[:kind]}/#{resource[:name]} in #{namespace}" }
        resource_yaml = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
        pods = KubectlClient::Get.pods_by_resource_labels(resource_yaml, namespace)
        Log.for(t.name).info { "Pod count for resource #{resource[:kind]}/#{resource[:name]} in #{namespace}: #{pods.size}" }
        pods.each do |pod|
          Log.for(t.name).info { "Inspecting pod: #{pod}" }
          resources_checked = true
          results = InitSystems.scan(pod)
          Log.for(t.name).info { "Pod scan result: #{results}" }
          if !results
            error_occurred = true
          else
            failed_cnf_resources = failed_cnf_resources + results
          end
        end
      end
    end

    if error_occurred
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "An error occurred during container inspection")
    elsif !resources_checked
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Container checks not executed")
    elsif failed_cnf_resources.size > 0
      failed_cnf_resources.each do |init_info|
        stdout_failure "#{init_info.kind}/#{init_info.name} has container '#{init_info.container}' with #{init_info.init_cmd} as init process"
      end
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Containers do not use specialized init systems (ভ_ভ) ރ")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Containers use specialized init systems 🖥️")
    end
  end
end
