# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "../utils/utils.cr"
require "../utils/disruption_budget.cr"

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
   "readiness",
   "pod_owner",
   "disruption_budget"
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
# litmus can target, with the label pair the engine has to select them by.
# Returns {passed, tested}: tested counts the targets litmus could address, so
# the caller reports not applicable when it is zero.
def chaos_resource_test(args, config, result, task_name : String, check_containers = true,
                        &block : (NamedTuple(kind: String, name: String, namespace: String), JSON::Any, JSON::Any, {String, String}) -> Bool) : {Bool, Int32}
  tested = 0
  passed = CNFManager.workload_resource_test(args, config, check_containers) do |resource, target, volumes|
    unless LITMUS_APPKINDS.includes?(resource[:kind].downcase)
      message = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: litmus cannot target a #{resource[:kind]}, #{task_name} is not applicable to it"
      Log.for(task_name).info { message }
      result.append_description(message)
      next true
    end
    # Litmus selects its target by a pod label; a workload whose template
    # carries none cannot be targeted, and that is a finding, reported the
    # same way by every chaos test (#2601).
    spec_labels = KubectlClient::Get.resource_spec_labels(resource[:kind], resource[:name], resource[:namespace])
    unless spec_labels.as_h? && !spec_labels.as_h.empty?
      result.add_impacted_resource(resource[:kind], resource[:name], resource[:namespace],
        reason: "no pod label in its template, litmus cannot target it for #{task_name}")
      next false
    end
    tested += 1
    # The label has to select the pods of this resource only. The first
    # selector label is often shared by a whole Helm release, and litmus then
    # picks a random pod of the release for every resource (#2657). A resource
    # that owns no pod has nothing to inject into and is left out.
    target_label = LitmusManager.resource_target_label(resource)
    unless target_label
      message = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]} owns no pod, #{task_name} has nothing to target"
      Log.for(task_name).warn { message }
      result.append_description(message)
      next true
    end
    block.call(resource, target, volumes, target_label)
  end
  {passed, tested}
end

# The container runtime of the cluster and its socket on the nodes, which
# the litmus helpers need to reach the target container. Both are cluster
# properties: when they cannot be established the test is not applicable,
# since the CNF is not what stops the fault from being injected. Reports
# that and returns nil in that case.
def chaos_container_runtime(result, task_name : String) : {String, String}?
  runtimes = KubectlClient::Get.container_runtimes
  container_runtime = LitmusManager.detect_runtime(runtimes)
  unless container_runtime
    result.na("#{task_name} not applicable: unsupported container runtime (#{runtimes.join(", ")})")
    return nil
  end
  socket_path = LitmusManager.detect_runtime_socket(container_runtime)
  unless socket_path
    result.na("#{task_name} not applicable: no #{container_runtime} socket found on the node, set #{LitmusManager::RUNTIME_SOCKET_ENV}")
    return nil
  end
  {container_runtime, socket_path}
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
    # The litmus helper reaches the target through the node's container
    # runtime; the engine names the runtime and socket the cluster has (#2103).
    runtime = chaos_container_runtime(result, t.name)
    next unless runtime
    container_runtime, socket_path = runtime

    #todo if args has list of labels to perform test on, go into pod specific mode
    #TODO tests should fail if cnf not installed
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _, target_label|
      Log.info { "Current Resource Name: #{resource["name"]} Type: #{resource["kind"]}" }
      app_namespace = resource[:namespace]

      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      test_passed = true

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
        test_name = LitmusManager.engine_name(resource["name"])
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        if args.named["pod-labels"]?
            template = ChaosTemplates::PodNetworkLatency.new(
              test_name,
              "#{chaos_experiment_name}",
              app_namespace,
              "#{resource["kind"].downcase}",
              "#{current_pod_key}",
              "#{current_pod_value}",
              container_runtime: container_runtime,
              socket_path: socket_path
        ).to_s
        else
          template = ChaosTemplates::PodNetworkLatency.new(
            test_name,
            "#{chaos_experiment_name}",
            app_namespace,
            "#{resource["kind"].downcase}",
            target_label[0],
            target_label[1],
            container_runtime: container_runtime,
            socket_path: socket_path
          ).to_s
        end
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
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
    # The litmus helper reaches the target through the node's container
    # runtime; the engine names the runtime and socket the cluster has (#2103).
    runtime = chaos_container_runtime(result, t.name)
    next unless runtime
    container_runtime, socket_path = runtime

    #TODO tests should fail if cnf not installed
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _, target_label|
      Log.info {"Current Resource Name: #{resource["name"]} Type: #{resource["kind"]}"}
      app_namespace = resource[:namespace]
      test_passed = true
      if test_passed
        LitmusManager.install_fault("pod-network-corruption", app_namespace, t.name)
 
        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-corruption"
        test_name = LitmusManager.engine_name(resource["name"])
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        template = ChaosTemplates::PodNetworkCorruption.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          target_label[0],
          target_label[1],
          container_runtime: container_runtime,
          socket_path: socket_path
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name, args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
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
    # The litmus helper reaches the target through the node's container
    # runtime; the engine names the runtime and socket the cluster has (#2103).
    runtime = chaos_container_runtime(result, t.name)
    next unless runtime
    container_runtime, socket_path = runtime

    #TODO tests should fail if cnf not installed
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _, target_label|
      app_namespace = resource[:namespace]
      Log.info{ "Current Resource Name: #{resource["name"]} Type: #{resource["kind"]} Namespace: #{resource["namespace"]}"}
      test_passed = true
      if test_passed
        LitmusManager.install_fault("pod-network-duplication", app_namespace, t.name)
        Log.for(t.name).debug { "annotating resource for chaos: #{resource["name"]}" }
        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-duplication"
        test_name = LitmusManager.engine_name(resource["name"])
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        template = ChaosTemplates::PodNetworkDuplication.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          target_label[0],
          target_label[1],
          container_runtime: container_runtime,
          socket_path: socket_path
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
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
    task_response, tested = chaos_resource_test(args, config, result, t.name, check_containers: false) do |resource, containers, _, target_label|
      app_namespace = resource[:namespace]

      # The fault is injected once per resource, into a container that can be
      # written to; the engine names it since litmus defaults to the first one.
      target_container = LitmusManager.filesystem_fault_target(containers)
      unless target_container
        pass_hardened_rootfs(result, resource, t.name)
        next true
      end

      injected += 1
      test_passed = true
      if test_passed
        LitmusManager.install_fault("disk-fill", app_namespace, t.name)

        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "disk-fill"
        test_name = LitmusManager.engine_name(resource["name"])
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        template = ChaosTemplates::DiskFill.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          target_label[0],
          target_label[1],
          target_container: target_container
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name, chaos_experiment_name, args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
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
    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _, target_label|
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      test_passed = true

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
        test_name = LitmusManager.engine_name(resource["name"])
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

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
          target_label[0],
          target_label[1],
          target_pod_name
        ).to_s
      end

        Log.info { "template: #{template}" }
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
      end
      test_passed=LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
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
    # The litmus helper reaches the target through the node's container
    # runtime; the engine names the runtime and socket the cluster has (#2103).
    runtime = chaos_container_runtime(result, t.name)
    next unless runtime
    container_runtime, socket_path = runtime

    task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _, target_label|
      app_namespace = resource[:namespace]
      test_passed = true
      if test_passed
        LitmusManager.install_fault("pod-memory-hog", app_namespace, t.name)

        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-memory-hog"
        target_pod_name = ""
        test_name = LitmusManager.engine_name(resource["name"])
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        template = ChaosTemplates::PodMemoryHog.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{resource["kind"].downcase}",
          target_label[0],
          target_label[1],
          target_pod_name,
          container_runtime: container_runtime,
          socket_path: socket_path
        ).to_s

        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
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
    runtime = chaos_container_runtime(result, t.name)
    next unless runtime
    container_runtime, socket_path = runtime

    injected = 0
    task_response, tested = chaos_resource_test(args, config, result, t.name, check_containers: false) do |resource, containers, _, target_label|
      app_namespace = resource[:namespace]

      # The fault is injected once per resource, into a container that can be
      # written to; the engine names it since litmus defaults to the first one.
      target_container = LitmusManager.filesystem_fault_target(containers)
      unless target_container
        pass_hardened_rootfs(result, resource, t.name)
        next true
      end

      deployment_label, deployment_label_value = target_label

      injected += 1
      test_passed = true
      if test_passed
        LitmusManager.install_fault("pod-io-stress", app_namespace, t.name)

        KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-io-stress"
        target_pod_name = ""
        chaos_test_name = LitmusManager.engine_name(resource["name"])
        chaos_result_name = "#{chaos_test_name}-#{chaos_experiment_name}"

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
          target_container: target_container
        ).to_s

        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(chaos_test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
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
    # The litmus helper reaches the target container through the node's
    # container runtime, like pod-io-stress: detect the runtime and its socket
    # and hand both to the engine. The test used to run only on a Docker
    # runtime and was skipped on every containerd or CRI-O cluster (#2579).
    runtime = chaos_container_runtime(result, t.name)
    next unless runtime
    container_runtime, socket_path = runtime

    begin
      task_response, tested = chaos_resource_test(args, config, result, t.name) do |resource, _, _, target_label|
        app_namespace = resource[:namespace]
        test_passed = true
        if test_passed
          LitmusManager.install_fault("pod-dns-error", app_namespace, t.name)

          KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

          chaos_experiment_name = "pod-dns-error"
          target_pod_name = ""
          test_name = LitmusManager.engine_name(resource["name"])
          chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

          template = ChaosTemplates::PodDnsError.new(
            test_name,
            "#{chaos_experiment_name}",
            app_namespace,
            "#{resource["kind"].downcase}",
            target_label[0],
            target_label[1],
            container_runtime: container_runtime,
            socket_path: socket_path
          ).to_s
          chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
          File.write(chaos_template_path, template)
          KubectlClient::Apply.file(chaos_template_path)
          LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
          test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace, result: result, target: "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}")
        end

        test_passed
      end
      chaos_verdict(result, t.name, task_response, tested)
    end
  end
end

desc "Check that every pod of the CNF is owned by a controller that recreates it (no bare Pods)"
scored_task "pod_owner",
  emoji: "⎈🧫" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # One finding per pod, keyed by namespace/name, however many of the CNF's
    # workloads select it.
    findings = {} of String => NamedTuple(name: String, namespace: String, reason: String)
    judged = Set(String).new

    CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      bare = resource[:kind].downcase == "pod"
      live = KubectlClient::Get.resource(resource[:kind], resource[:name], resource[:namespace])
      KubectlClient::Get.pods_by_resource_labels(live, resource[:namespace]).each do |pod|
        # A pod already being deleted is on its way out, not a pod of the CNF.
        next if pod.dig?("metadata", "deletionTimestamp")
        # A Helm hook's pod (a chart's *-test-connection after `helm test`) often
        # carries the workload's selector labels; hooks are not part of the
        # CNF's workloads, here as in the manifest.
        next if pod.dig?("metadata", "annotations", "helm.sh/hook")
        pod_name = pod.dig?("metadata", "name").try(&.as_s?) || next
        key = "#{resource[:namespace]}/#{pod_name}"
        judged << key
        owners = pod.dig?("metadata", "ownerReferences").try(&.as_a?) || [] of JSON::Any
        next if owners.any? { |o| o.dig?("controller").try(&.as_bool?) == true }
        # The manifest's own word wins: "declared as a bare Pod" points at the
        # fix, whichever workload's selector reached the pod first.
        next if findings.has_key?(key) && !bare
        reason = bare ? "declared as a bare Pod in the CNF's manifest" : "has no owner reference with controller: true"
        findings[key] = {name: pod_name, namespace: resource[:namespace],
                         reason: "#{reason}: no controller recreates it when its node fails or is drained"}
      end
      true
    end

    if judged.empty?
      result.append_remediation("Make sure the CNF's pods are running (a workload scaled to zero has none), then run the test again.")
      result.skipped("No pod of the CNF could be read; pod ownership could not be checked")
    elsif findings.empty?
      result.passed("All #{judged.size} pod(s) of the CNF are owned by a controller")
    else
      findings.each_value do |f|
        result.add_impacted_resource("Pod", f[:name], f[:namespace], reason: f[:reason])
      end
      result.append_remediation("Run the pods through a Deployment, StatefulSet, DaemonSet or Job, so that a controller recreates them when their node fails or is drained, and they can be scaled and rolled out.")
      result.failed("Found #{findings.size} of #{judged.size} pod(s) of the CNF not owned by a controller")
    end
  end
end

desc "Check that the CNF's replicated workloads stay up through a node drain: a disruption budget that allows an eviction, and replicas spread over nodes"
scored_task "disruption_budget",
  emoji: "⎈🧫" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    resources = CNFManager.cnf_resource_ymls(args, config).map { |y| JSON.parse(y.to_json) }
    namespace_of = ->(r : JSON::Any) { r.dig?("metadata", "namespace").try(&.as_s?) || CLUSTER_DEFAULT_NAMESPACE }
    kind_of = ->(r : JSON::Any) { r.dig?("kind").try(&.as_s?) }

    hpas = resources.select { |r| kind_of.call(r) == "HorizontalPodAutoscaler" }.map { |r| {r, namespace_of.call(r)} }
    # DaemonSets are left out: a drain does not evict them.
    workloads = resources.select { |r| ["Deployment", "StatefulSet"].includes?(kind_of.call(r)) }.map do |r|
      ns = namespace_of.call(r)
      labels = (r.dig?("spec", "template", "metadata", "labels").try(&.as_h?) || {} of String => JSON::Any)
        .transform_values { |v| v.as_s? || v.to_s }
      DisruptionBudget::Workload.new(kind_of.call(r).not_nil!, r.dig("metadata", "name").as_s, ns,
        DisruptionBudget.replicas(r, ns, hpas), labels,
        r.dig?("spec", "template", "spec") || JSON::Any.new({} of String => JSON::Any))
    end

    # Budgets from the manifest, and those live in the CNF's namespaces (an
    # operator may create them); the live object wins.
    budgets = {} of String => DisruptionBudget::Budget
    resources.select { |r| kind_of.call(r) == "PodDisruptionBudget" }.each do |r|
      ns = namespace_of.call(r)
      name = r.dig("metadata", "name").as_s
      budgets["#{ns}/#{name}"] = DisruptionBudget::Budget.new(name, ns, r["spec"]? || JSON::Any.new({} of String => JSON::Any))
    end
    (workloads.map(&.namespace) + budgets.values.map(&.namespace)).uniq.each do |ns|
      live = KubectlClient::ShellCMD.run("kubectl get poddisruptionbudgets -n #{ns} -o json", Log.for(t.name))
      next unless live[:status].success?
      (JSON.parse(live[:output])["items"]?.try(&.as_a?) || [] of JSON::Any).each do |item|
        name = item.dig("metadata", "name").as_s
        budgets["#{ns}/#{name}"] = DisruptionBudget::Budget.new(name, ns, item["spec"]? || JSON::Any.new({} of String => JSON::Any))
      end
    end

    evaluation = DisruptionBudget.evaluate(workloads, budgets.values)
    evaluation.details.each { |d| result.append_description(d) }
    if !evaluation.applicable
      result.na("The CNF has no workload with more than one replica and no PodDisruptionBudget")
    elsif evaluation.findings.empty?
      result.passed("Every replicated workload is covered by a disruption budget and spread over nodes, and no budget blocks a drain")
    else
      evaluation.findings.each do |f|
        result.add_impacted_resource(f.kind, f.name, f.namespace, reason: f.reason)
      end
      result.append_remediation("For each workload with more than one replica, add a PodDisruptionBudget that selects its pods and allows at least one eviction (for example maxUnavailable: 1), and spread its replicas over nodes with a required podAntiAffinity or a topologySpreadConstraints entry on kubernetes.io/hostname with whenUnsatisfiable: DoNotSchedule. A budget must not set maxUnavailable: 0 or a minAvailable equal to its pods, nor leave both unset.")
      result.failed("Found #{evaluation.findings.size} workload(s) or budget(s) that would not keep the CNF up through a node drain")
    end
  end
end
