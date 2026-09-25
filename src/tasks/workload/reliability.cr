# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "../utils/utils.cr"

desc "The CNF test suite checks to see if the CNFs are resilient to failures."
category_task "resilience", [
   "pod_network_latency",
   "pod_network_corruption",
   "disk_fill",
   "pod_delete",
   "pod_memory_hog",
   "pod_io_stress",
   "pod_dns_error",
   "pod_network_duplication",
   "liveness",
   "readiness"
  ],
  title: "Reliability, Resilience, and Availability"

def run_probe_task(t, args, probe_type : String)
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, _|
      resource_ref = "#{resource[:kind]}/#{resource[:name]}"
      probe_key = "#{probe_type}Probe"
      resource_has_probe = false
      containers_without_probe = [] of String

      containers.as_a.each do |container|
        begin
          container.as_h[probe_key].as_h
          resource_has_probe = true
        rescue ex
          containers_without_probe << container["name"].as_s
        end
      end

      containers_with_probe = containers.as_a.map { |c| c["name"].as_s } - containers_without_probe
      Log.for(t.name).info { "Containers in #{resource_ref} missing #{probe_key}: #{containers_without_probe.empty? ? "none" : containers_without_probe.join(", ")}" }

      if resource_has_probe
        # A pass says what satisfied it, so the verdict can be reviewed.
        result.append_description("#{resource_ref} in #{resource[:namespace]}: #{probe_type} probe on #{containers_with_probe.join(", ")}")
      else
        result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace],
          reason: "no #{probe_type} probe on any container (#{containers_without_probe.join(", ")})")
      end

      Log.for(t.name).info { "Resource #{resource_ref} has at least one #{probe_key}?: #{resource_has_probe}" }
      resource_has_probe
    end

    if task_response
      result.passed("All workload resources have at least one container with a #{probe_type} probe")
    else
      result.failed("One or more workload resources have no containers with a #{probe_type} probe")
    end
  end
end

desc "Check that each workload resource includes at least one container with a liveness probe defined"
scored_task "liveness",
  type: CNFManager::TestType::Essential,
  emoji: "⎈🧫" do |t, args|
  run_probe_task(t, args, "liveness")
end

desc "Check that each workload resource includes at least one container with a readiness probe defined"
scored_task "readiness",
  type: CNFManager::TestType::Essential,
  emoji: "⎈🧫" do |t, args|
  run_probe_task(t, args, "readiness")
end

# Kinds a litmus ChaosEngine can name as its appkind. Pod and ReplicaSet are
# workload kinds for the suite but not for litmus, whose annotation check
# rejects the engine outright ("appkind is not supported"), so a chaos test
# reports such a resource as not applicable instead of failing on an engine
# error.
LITMUS_APPKINDS = ["deployment", "statefulset", "daemonset"]

# Runs a chaos test over the CNF's workload resources, yielding only those
# litmus can target. Returns {passed, tested}: tested counts the targets the
# block saw, so the caller reports not applicable when it is zero.
def chaos_resource_test(args, config, result, task_name : String, check_containers = true,
                        &block : (NamedTuple(kind: String, name: String, namespace: String), JSON::Any, JSON::Any) -> Bool) : {Bool, Int32}
  tested = 0
  passed = CNFManager.workload_resource_test(args, config, check_containers) do |resource, target, volumes|
    unless LITMUS_APPKINDS.includes?(resource[:kind].downcase)
      message = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: litmus cannot target a #{resource[:kind]}, #{task_name} is not applicable to it"
      Log.for(task_name).info { message }
      result.append_description(message)
      next true
    end
    tested += 1
    block.call(resource, target, volumes)
  end
  {passed, tested}
end

# Verdict shared by the chaos tests: not applicable when litmus could target
# nothing, otherwise pass or fail on the experiments.
def chaos_verdict(result, task_name : String, passed : Bool, tested : Int32, passed_message : String? = nil)
  if tested == 0
    result.na("#{task_name} not applicable: no Deployment, StatefulSet or DaemonSet for litmus to target")
  elsif passed
    result.passed(passed_message || "#{task_name} chaos test passed")
  else
    result.failed("#{task_name} chaos test failed")
  end
end

desc "Does the CNF crash when network latency occurs"
scored_task "pod_network_latency",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    #todo if args has list of labels to perform test on, go into pod specific mode
    #TODO tests should fail if cnf not installed
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _|
      Log.info { "Current Resource Name: #{resource["name"]} Type: #{resource["kind"]}" }
      app_namespace = resource[:namespace]

      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        result.append_description("No resource label was found for resource: #{resource["name"]}")
        test_passed = false
      end

      current_pod_key = ""
      current_pod_value = ""
      if args.named["pod-labels"]?
          pod_label = args.named["pod-labels"]?
          match_array = pod_label.to_s.split(",")

        test_passed = match_array.any? do |key_value|
          key, value = key_value.split("=")
          if spec_labels.as_h.has_key?(key) && spec_labels[key] == value
            current_pod_key = key
            current_pod_value = value
            Log.info { "Match found for key: #{key} and value: #{value}"}
            true
          else
            Log.info { "Match not found for key: #{key} and value: #{value}"}
            false
          end
        end
      end

      Log.info { "Spec Hash: #{args.named["pod-labels"]?}" }


      if test_passed
        Log.info { "Running for: #{spec_labels}"}
        Log.info { "Spec Hash: #{args.named["pod-labels"]?}" }
        LitmusManager.install_fault("pod-network-latency", app_namespace, t.name)

        #TODO Use Labels to Annotate, not resource["name"]
        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-latency"
        test_name = "#{resource["name"]}-#{Random::Secure.hex(4)}"
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        #spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        if args.named["pod-labels"]?
            template = ChaosTemplates::PodNetworkLatency.new(
              test_name,
              "#{chaos_experiment_name}",
              app_namespace,
              "#{resource["kind"].downcase}",
              "#{current_pod_key}",
              "#{current_pod_value}"
        ).to_s
        else
          template = ChaosTemplates::PodNetworkLatency.new(
            test_name,
            "#{chaos_experiment_name}",
            app_namespace,
            "#{resource["kind"].downcase}",
            "#{spec_labels.as_h.first_key}",
            "#{spec_labels.as_h.first_value}"
          ).to_s
        end
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result)
      end

      test_passed
    end
    unless args.named["pod-labels"]?
        #todo if in pod specific mode, dont do upserts and resp = ""
        chaos_verdict(result, t.name, task_response, tested)
    end

  end
end

desc "Does the CNF crash when network corruption occurs"
scored_task "pod_network_corruption",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    #TODO tests should fail if cnf not installed
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _|
      Log.info {"Current Resource Name: #{resource["name"]} Type: #{resource["kind"]}"}
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        result.append_description("No resource label was found for resource: #{resource["name"]}")
        test_passed = false
      end
      if test_passed
        LitmusManager.install_fault("pod-network-corruption", app_namespace, t.name)
 
        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-corruption"
        test_name = "#{resource["name"]}-#{Random.rand(99)}"
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        template = ChaosTemplates::PodNetworkCorruption.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}"
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name, args, namespace: app_namespace, result: result)
      end

      test_passed
    end
    chaos_verdict(result, t.name, task_response, tested)
  end
end

desc "Does the CNF crash when network duplication occurs"
scored_task "pod_network_duplication",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    #TODO tests should fail if cnf not installed
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _|
      app_namespace = resource[:namespace]
      Log.info{ "Current Resource Name: #{resource["name"]} Type: #{resource["kind"]} Namespace: #{resource["namespace"]}"}
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "no resource label found")
        test_passed = false
      end
      if test_passed
        LitmusManager.install_fault("pod-network-duplication", app_namespace, t.name)
        Log.for(t.name).debug { "annotating resource for chaos: #{resource["name"]}" }
        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-duplication"
        test_name = "#{resource["name"]}-#{Random.rand(99)}"
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        template = ChaosTemplates::PodNetworkDuplication.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}"
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result)
      end

      test_passed
    end
    chaos_verdict(result, t.name, task_response, tested)
  end
end

# A workload whose every container mounts a read-only root file system cannot
# be written into by disk_fill's `dd` or pod_io_stress's `fio`. Being unable
# to fill or stress its file system is the very property those faults probe,
# so the resource passes without an experiment and the reason is recorded.
def pass_hardened_rootfs(result, resource, task_name : String)
  message = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: every container has a read-only root file system, #{task_name} cannot write into it"
  Log.for(task_name).info { message }
  result.append_description(message)
end

desc "Does the CNF crash when disk fill occurs"
scored_task "disk_fill",
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    injected = 0
    task_response, tested = chaos_resource_test(args, config, result, t.name, check_containers: false) do |resource, containers, _|
      app_namespace = resource[:namespace]

      # The fault is injected once per resource, into a container that can be
      # written to; the engine names it since litmus defaults to the first one.
      target_container = LitmusManager.filesystem_fault_target(containers)
      unless target_container
        pass_hardened_rootfs(result, resource, t.name)
        next true
      end

      injected += 1
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "no resource label found for #{t.name} test")
        test_passed = false
      end
      if test_passed
        LitmusManager.install_fault("disk-fill", app_namespace, t.name)

        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "disk-fill"
        test_name = "#{resource["name"]}-#{Random.rand(99)}"
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        Log.for("#{test_name}:spec_labels").info { "Spec labels for chaos template. Key: #{spec_labels.first_key}; Value: #{spec_labels.first_value}" }
        # todo change to use all labels instead of first label
        template = ChaosTemplates::DiskFill.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}",
          target_container: target_container
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name, chaos_experiment_name, args, namespace: app_namespace, result: result)
      end

      test_passed
    end
    hardened_only = injected == 0 ? "disk_fill chaos test passed: every container has a read-only root file system" : nil
    chaos_verdict(result, t.name, task_response, tested, hardened_only)
  end
end

desc "Does the CNF crash when pod-delete occurs"
scored_task "pod_delete",
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    #todo clear all annotations
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _|
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "no resource label found for #{t.name} test")
        test_passed = false
      end

      current_pod_key = ""
      current_pod_value = ""
      if args.named["pod-labels"]?
          pod_label = args.named["pod-labels"]?
          match_array = pod_label.to_s.split(",")

        test_passed = match_array.any? do |key_value|
          key, value = key_value.split("=")
          if spec_labels.as_h.has_key?(key) && spec_labels[key] == value
            current_pod_key = key
            current_pod_value = value
            Log.info { "Match found for key: #{key} and value: #{value}" }
            true
          else
            Log.info { "Match not found for key: #{key} and value: #{value}" }
            false
          end
        end
      end

      Log.info { "Spec Hash: #{args.named["pod-labels"]?}" }


      if test_passed
        Log.info { "Running for: #{spec_labels}"}
        Log.info { "Spec Hash: #{args.named["pod-labels"]?}" }
        LitmusManager.install_fault("pod-delete", app_namespace, t.name)

        Log.info { "resource: #{resource["name"]}" }
        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-delete"
        target_pod_name = ""
        test_name = "#{resource["name"]}-#{Random.rand(99)}" 
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        # spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
      if args.named["pod-labels"]?
        template = ChaosTemplates::PodDelete.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          "#{current_pod_key}",
          "#{current_pod_value}",
          target_pod_name
        ).to_s
      else
        template = ChaosTemplates::PodDelete.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          "#{spec_labels.as_h.first_key}",
          "#{spec_labels.as_h.first_value}",
          target_pod_name
        ).to_s
      end

        Log.info { "template: #{template}" }
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
      end
      test_passed=LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result)
      test_passed
    end
    unless args.named["pod-labels"]?
        chaos_verdict(result, t.name, task_response, tested)
    end
  end
end

desc "Does the CNF crash when pod-memory-hog occurs"
scored_task "pod_memory_hog",
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _|
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "no resource label found for #{t.name} test")
        test_passed = false
      end
      if test_passed
        LitmusManager.install_fault("pod-memory-hog", app_namespace, t.name)

        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-memory-hog"
        target_pod_name = ""
        test_name = "#{resource["name"]}-#{Random.rand(99)}" 
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        template = ChaosTemplates::PodMemoryHog.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}",
          target_pod_name
        ).to_s

        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result)
      end
      test_passed
    end
    chaos_verdict(result, t.name, task_response, tested)
  end
end

desc "Does the CNF crash when pod-io-stress occurs"
scored_task "pod_io_stress",
  type: CNFManager::TestType::Bonus,
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # The litmus helper injects the IO stress through the node's container
    # runtime, so the engine must advertise the actual runtime and its socket
    # rather than a hard-coded containerd path. Both are cluster properties:
    # when they cannot be established the test is not applicable, since the
    # CNF is not what stops the fault from being injected.
    runtimes = KubectlClient::Get.container_runtimes
    container_runtime = LitmusManager.detect_runtime(runtimes)
    unless container_runtime
      result.na("pod_io_stress not applicable: unsupported container runtime (#{runtimes.join(", ")})")
      next
    end
    socket_path = LitmusManager.detect_runtime_socket(container_runtime)
    unless socket_path
      result.na("pod_io_stress not applicable: no #{container_runtime} socket found on the node, set #{LitmusManager::RUNTIME_SOCKET_ENV}")
      next
    end

    injected = 0
    task_response, tested = chaos_resource_test(args, config, result, t.name, check_containers: false) do |resource, containers, _|
      app_namespace = resource[:namespace]

      # The fault is injected once per resource, into a container that can be
      # written to; the engine names it since litmus defaults to the first one.
      target_container = LitmusManager.filesystem_fault_target(containers)
      unless target_container
        pass_hardened_rootfs(result, resource, t.name)
        next true
      end

      # A label that selects exactly this resource's pods; none when it owns
      # no pod, in which case there is nothing to stress and the resource is
      # left out rather than stressed through a random pod of the release.
      target_label = LitmusManager.resource_target_label(resource)
      unless target_label
        message = "#{resource[:kind]}/#{resource[:name]} in #{app_namespace} owns no pod, nothing to stress"
        Log.for(t.name).warn { message }
        result.append_description(message)
        next true
      end
      deployment_label, deployment_label_value = target_label

      injected += 1
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "no resource label found for #{t.name} test")
        test_passed = false
      end
      if test_passed
        LitmusManager.install_fault("pod-io-stress", app_namespace, t.name)

        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-io-stress"
        target_pod_name = ""
        chaos_test_name = "#{resource["name"]}-#{Random.rand(99)}"
        chaos_result_name = "#{chaos_test_name}-#{chaos_experiment_name}"
        filesystem_utilization_percentage = LitmusManager.filesystem_utilization_percentage(containers, resource, app_namespace, target_container)
        volume_mount_path = filesystem_utilization_percentage ? LitmusManager::POD_IO_STRESS_VOLUME_MOUNT_PATH : ""

        template = ChaosTemplates::PodIoStress.new(
          chaos_test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          deployment_label,
          deployment_label_value,
          target_pod_name,
          container_runtime: container_runtime,
          socket_path: socket_path,
          target_container: target_container,
          filesystem_utilization_percentage: filesystem_utilization_percentage || "",
          volume_mount_path: volume_mount_path
        ).to_s

        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(chaos_test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result)
      end

      test_passed
    end
    hardened_only = injected == 0 ? "pod_io_stress chaos test passed: every container has a read-only root file system" : nil
    chaos_verdict(result, t.name, task_response, tested, hardened_only)
  end
ensure
  # This ensures that no litmus-related resources are left behind after the test is run.
  # Only the default namespace is cleaned up.
  begin
    KubectlClient::Delete.resource("all", labels: {"app.kubernetes.io/part-of" => "litmus"})
  rescue ex: KubectlClient::ShellCMD::NotFoundError
    Log.warn { "Cannot delete resources with labels \"app.kubernetes.io/part-of\" => \"litmus\". Resource not found." }
  end 
end


desc "Does the CNF crash when pod-dns-error occurs"
scored_task "pod_dns_error",
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    runtimes = KubectlClient::Get.container_runtimes
    Log.info { "pod_dns_error runtimes: #{runtimes}" }
    if runtimes.find{|r| r.downcase.includes?("docker")}
      task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _|
        app_namespace = resource[:namespace]
        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
        if spec_labels.as_h? && spec_labels.as_h.size > 0
          test_passed = true
        else
          result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "no resource label found for #{t.name} test")
          test_passed = false
        end
        if test_passed
          LitmusManager.install_fault("pod-dns-error", app_namespace, t.name)

          KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

          chaos_experiment_name = "pod-dns-error"
          target_pod_name = ""
          test_name = "#{resource["name"]}-#{Random.rand(99)}" 
          chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

          spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
          template = ChaosTemplates::PodDnsError.new(
            test_name,
            "#{chaos_experiment_name}",
            app_namespace,
            "#{resource["kind"].downcase}",
            "#{spec_labels.first_key}",
            "#{spec_labels.first_value}"
          ).to_s
          chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
          File.write(chaos_template_path, template)
          KubectlClient::Apply.file(chaos_template_path)
          LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
          test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result)
        end

        test_passed
      end
      chaos_verdict(result, t.name, task_response, tested)
    else
      result.skipped("pod_dns_error docker runtime not found")
    end
  end
end
