# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "../utils/utils.cr"

desc "The CNF test suite checks to see if the CNFs are resilient to failures."
 task "resilience", [
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
  ] do |t, args|
  Log.debug { "resilience" }
  Log.trace { "resilience args.raw: #{args.raw}" }
  Log.trace { "resilience args.named: #{args.named}" }
  stdout_score("resilience", "Reliability, Resilience, and Availability")
  case "#{ARGV.join(" ")}" 
  when /reliability/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end

def run_probe_task(t, args, probe_type : String)
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers|
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

      containers_without_probe_joined = containers_without_probe.empty? ? "none" : containers_without_probe.join(", ")
      Log.for(t.name).info { "Containers in #{resource_ref} missing #{probe_key}: #{containers_without_probe_joined}" }

      unless resource_has_probe
        stdout_failure("No #{probe_type} probe found for any container in #{resource_ref} in #{resource[:namespace]} namespace")
      end

      Log.for(t.name).info { "Resource #{resource_ref} has at least one #{probe_key}?: #{resource_has_probe}" }
      resource_has_probe
    end

    if task_response
      CNFManager::TestCaseResult.new(
        CNFManager::ResultStatus::Passed,
        "All workload resources have at least one container with a #{probe_type} probe"
      )
    else
      CNFManager::TestCaseResult.new(
        CNFManager::ResultStatus::Failed,
        "One or more workload resources have no containers with a #{probe_type} probe"
      )
    end
  end
end

desc "Check that each workload resource includes at least one container with a liveness probe defined"
task "liveness" do |t, args|
  run_probe_task(t, args, "liveness")
end

desc "Check that each workload resource includes at least one container with a readiness probe defined"
task "readiness" do |t, args|
  run_probe_task(t, args, "readiness")
end

desc "Does the CNF crash when network latency occurs"
task "pod_network_latency", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    #todo if args has list of labels to perform test on, go into pod specific mode
    #TODO tests should fail if cnf not installed
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      Log.info { "Current Resource Name: #{resource["name"]} Type: #{resource["kind"]}" }
      app_namespace = resource[:namespace]

      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0 && resource["kind"] == "Deployment"
        test_passed = true
      else
        stdout_failure("Resource is not a Deployment or no resource label was found for resource: #{resource["name"]}")
        test_passed = false
      end

      current_pod_key = ""
      current_pod_value = ""
      if args.named["pod_labels"]?
          pod_label = args.named["pod_labels"]?
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

      Log.info { "Spec Hash: #{args.named["pod_labels"]?}" }


      if test_passed
        Log.info { "Running for: #{spec_labels}"}
        Log.info { "Spec Hash: #{args.named["pod_labels"]?}" }
        experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/pod-network-latency/fault.yaml"
        rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/pod-network-latency/rbac.yaml"
        
        experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
        KubectlClient::Apply.file(experiment_path, namespace: app_namespace)
        rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
        rbac_yaml = File.read(rbac_path)
        rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
        File.write(rbac_path, rbac_yaml)
        KubectlClient::Apply.file(rbac_path)

        #TODO Use Labels to Annotate, not resource["name"]
        KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-latency"
        test_name = "#{resource["name"]}-#{Random::Secure.hex(4)}"
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        #spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        if args.named["pod_labels"]?
            template = ChaosTemplates::PodNetworkLatency.new(
              test_name,
              "#{chaos_experiment_name}",
              app_namespace,
              "#{current_pod_key}",
              "#{current_pod_value}"
        ).to_s
        else
          template = ChaosTemplates::PodNetworkLatency.new(
            test_name,
            "#{chaos_experiment_name}",
            app_namespace,
            "#{spec_labels.as_h.first_key}",
            "#{spec_labels.as_h.first_value}"
          ).to_s
        end
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace)
      end
    end
    unless args.named["pod_labels"]?
        #todo if in pod specific mode, dont do upserts and resp = ""
        if task_response
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "pod_network_latency chaos test passed")
        else
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "pod_network_latency chaos test failed")
        end
    end

  end
end

desc "Does the CNF crash when network corruption occurs"
task "pod_network_corruption", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    #TODO tests should fail if cnf not installed
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      Log.info {"Current Resource Name: #{resource["name"]} Type: #{resource["kind"]}"}
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0 && resource["kind"] == "Deployment"
        test_passed = true
      else
        stdout_failure("Resource is not a Deployment or no resource label was found for resource: #{resource["name"]}")
        test_passed = false
      end
      if test_passed
        experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/pod-network-corruption/fault.yaml"
        rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/pod-network-corruption/rbac.yaml"
        experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
        KubectlClient::Apply.file(experiment_path, namespace: app_namespace)
        rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
        rbac_yaml = File.read(rbac_path)
        rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
        File.write(rbac_path, rbac_yaml)
        KubectlClient::Apply.file(rbac_path)
 
        KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-corruption"
        test_name = "#{resource["name"]}-#{Random.rand(99)}"
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        template = ChaosTemplates::PodNetworkCorruption.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}"
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name, args, namespace: app_namespace)
      end
    end
    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "pod_network_corruption chaos test passed")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "pod_network_corruption chaos test failed")
    end
  end
end

desc "Does the CNF crash when network duplication occurs"
task "pod_network_duplication", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    #TODO tests should fail if cnf not installed
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      app_namespace = resource[:namespace]
      Log.info{ "Current Resource Name: #{resource["name"]} Type: #{resource["kind"]} Namespace: #{resource["namespace"]}"}
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0 && resource["kind"] == "Deployment"
        test_passed = true
      else
        stdout_failure("Resource is not a Deployment or no resource label was found for resource: #{resource["kind"]}/#{resource["name"]} in #{resource["namespace"]} namespace")
        test_passed = false
      end
      if test_passed
        experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/pod-network-duplication/fault.yaml"
        rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/pod-network-duplication/rbac.yaml"

        experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
        KubectlClient::Apply.file(experiment_path, namespace: app_namespace)

        rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
        rbac_yaml = File.read(rbac_path)
        rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
        File.write(rbac_path, rbac_yaml)
        KubectlClient::Apply.file(rbac_path)
        puts resource["name"]
        KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-network-duplication"
        test_name = "#{resource["name"]}-#{Random.rand(99)}"
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        template = ChaosTemplates::PodNetworkDuplication.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}"
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace)
      end
    end
    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "pod_network_duplication chaos test passed")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "pod_network_duplication chaos test failed")
    end
  end
end

desc "Does the CNF crash when disk fill occurs"
task "disk_fill", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        stdout_failure("No resource label found for #{t.name} test for resource: #{resource["kind"]}/#{resource["name"]} in #{resource["namespace"]} namespace")
        test_passed = false
      end
      if test_passed
        experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/disk-fill/fault.yaml"
        rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/disk-fill/rbac.yaml"

        experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
        KubectlClient::Apply.file(experiment_path, namespace: app_namespace)

        rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
        rbac_yaml = File.read(rbac_path)
        rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
        File.write(rbac_path, rbac_yaml)
        KubectlClient::Apply.file(rbac_path)

        KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

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
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}"
        ).to_s
        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name, chaos_experiment_name, args, namespace: app_namespace)
      end
      test_passed
    end
    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "disk_fill chaos test passed")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "disk_fill chaos test failed")
    end
  end
end

desc "Does the CNF crash when pod-delete occurs"
task "pod_delete", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    #todo clear all annotations
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        stdout_failure("No resource label found for #{t.name} test for resource: #{resource["kind"]}/#{resource["name"]} in #{resource["namespace"]} namespace")
        test_passed = false
      end

      current_pod_key = ""
      current_pod_value = ""
      if args.named["pod_labels"]?
          pod_label = args.named["pod_labels"]?
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

      Log.info { "Spec Hash: #{args.named["pod_labels"]?}" }


      if test_passed
        Log.info { "Running for: #{spec_labels}"}
        Log.info { "Spec Hash: #{args.named["pod_labels"]?}" }
        experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/pod-delete/fault.yaml"
        rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/pod-delete/rbac.yaml"

        experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")

        rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
        rbac_yaml = File.read(rbac_path)
        rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
        File.write(rbac_path, rbac_yaml)


        KubectlClient::Apply.file(experiment_path, namespace: app_namespace)
        KubectlClient::Apply.file(rbac_path)

        Log.info { "resource: #{resource["name"]}" }
        KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-delete"
        target_pod_name = ""
        test_name = "#{resource["name"]}-#{Random.rand(99)}" 
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        # spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
      if args.named["pod_labels"]?
        template = ChaosTemplates::PodDelete.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{current_pod_key}",
          "#{current_pod_value}",
          target_pod_name
        ).to_s
      else
        template = ChaosTemplates::PodDelete.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
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
      test_passed=LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace)
    end
    unless args.named["pod_labels"]?
        if task_response
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "pod_delete chaos test passed")
        else
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "pod_delete chaos test failed")
        end
    end
  end
end

desc "Does the CNF crash when pod-memory-hog occurs"
task "pod_memory_hog", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        stdout_failure("No resource label found for #{t.name} test for resource: #{resource["kind"]}/#{resource["name"]} in #{resource["namespace"]} namespace")
        test_passed = false
      end
      if test_passed
        experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/pod-memory-hog/fault.yaml"
        rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/pod-memory-hog/rbac.yaml"

        experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
        KubectlClient::Apply.file(experiment_path, namespace: app_namespace)

        rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
        rbac_yaml = File.read(rbac_path)
        rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
        File.write(rbac_path, rbac_yaml)
        KubectlClient::Apply.file(rbac_path)

        KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-memory-hog"
        target_pod_name = ""
        test_name = "#{resource["name"]}-#{Random.rand(99)}" 
        chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        template = ChaosTemplates::PodMemoryHog.new(
          test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}",
          target_pod_name
        ).to_s

        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace)
      end
      test_passed
    end
    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "pod_memory_hog chaos test passed")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "pod_memory_hog chaos test failed")
    end
  end
end

desc "Does the CNF crash when pod-io-stress occurs"
task "pod_io_stress", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      app_namespace = resource[:namespace]
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
      if spec_labels.as_h? && spec_labels.as_h.size > 0
        test_passed = true
      else
        stdout_failure("No resource label found for #{t.name} test for resource: #{resource["name"]} in #{resource["namespace"]}")
        test_passed = false
      end
      if test_passed
        experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/pod-io-stress/fault.yaml"
        rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/pod-io-stress/rbac.yaml"

        experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
        KubectlClient::Apply.file(experiment_path, namespace: app_namespace)

        rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
        rbac_yaml = File.read(rbac_path)
        rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
        File.write(rbac_path, rbac_yaml)
        KubectlClient::Apply.file(rbac_path)

        KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

        chaos_experiment_name = "pod-io-stress"
        target_pod_name = ""
        chaos_test_name = "#{resource["name"]}-#{Random.rand(99)}" 
        chaos_result_name = "#{chaos_test_name}-#{chaos_experiment_name}"

        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
        template = ChaosTemplates::PodIoStress.new(
          chaos_test_name,
          "#{chaos_experiment_name}",
          app_namespace,
          "#{spec_labels.first_key}",
          "#{spec_labels.first_value}",
          target_pod_name
        ).to_s

        chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
        File.write(chaos_template_path, template)
        KubectlClient::Apply.file(chaos_template_path)
        LitmusManager.wait_for_test(chaos_test_name, chaos_experiment_name, args, namespace: app_namespace)
        test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace)
      end
    end
    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "pod_io_stress chaos test passed")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "pod_io_stress chaos test failed")
    end
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
task "pod_dns_error", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    runtimes = KubectlClient::Get.container_runtimes
    Log.info { "pod_dns_error runtimes: #{runtimes}" }
    if runtimes.find{|r| r.downcase.includes?("docker")}
      task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
        app_namespace = resource[:namespace]
        spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])
        if spec_labels.as_h? && spec_labels.as_h.size > 0
          test_passed = true
        else
          stdout_failure("No resource label found for #{t.name} test for resource: #{resource["kind"]}/#{resource["name"]} in #{resource["namespace"]} namespace")
          test_passed = false
        end
        if test_passed
          experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/pod-dns-error/fault.yaml"
          rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/pod-dns-error/rbac.yaml"

          experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
          KubectlClient::Apply.file(experiment_path, namespace: app_namespace)

          rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
          rbac_yaml = File.read(rbac_path)
          rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
          File.write(rbac_path, rbac_yaml)
          KubectlClient::Apply.file(rbac_path)

          KubectlClient::Utils.annotate("deployment", resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

          chaos_experiment_name = "pod-dns-error"
          target_pod_name = ""
          test_name = "#{resource["name"]}-#{Random.rand(99)}" 
          chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

          spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"]).as_h
          template = ChaosTemplates::PodDnsError.new(
            test_name,
            "#{chaos_experiment_name}",
            app_namespace,
            "#{spec_labels.first_key}",
            "#{spec_labels.first_value}"
          ).to_s
          chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
          File.write(chaos_template_path, template)
          KubectlClient::Apply.file(chaos_template_path)
          LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
          test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace)
        end
      end
      if task_response
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "pod_dns_error chaos test passed")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "pod_dns_error chaos test failed")
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "pod_dns_error docker runtime not found")
    end
  end
end
