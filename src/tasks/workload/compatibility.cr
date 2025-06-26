# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../../modules/docker_client"
require "../utils/utils.cr"


desc "The CNF test suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s kubectl"
task "compatibility", ["helm_chart_valid", "helm_chart_published", "helm_deploy", "cni_compatible", "increase_decrease_capacity", "rollback", "deprecated_k8s_features"].concat(ROLLING_VERSION_CHANGE_TEST_NAMES) do |_, args|
  stdout_score("compatibility", "Compatibility, Installability, and Upgradeability")
  case "#{ARGV.join(" ")}" 
  when /compatibility/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end

end
ROLLING_VERSION_CHANGE_TEST_NAMES.each do |tn|
  pretty_test_name = tn.split(/:|_/).join(" ")
  pretty_test_name_capitalized = tn.split(/:|_/).map(&.capitalize).join(" ")

  desc "Test if the CNF containers are loosely coupled by performing a #{pretty_test_name}"
  task "#{tn}" do |t, args|
    CNFManager::Task.task_runner(args, task: t) do |args, config|
      container_names = config.common.container_names
      Log.for(t.name).debug { "container_names: #{container_names}" }
      update_applied = true
      unless container_names
        puts "Please add a container names set of entries into your cnf-testsuite.yml".colorize(:red)
        update_applied = false
      end

      # TODO use tag associated with image name string (e.g. busybox:v1.7.9) as the version tag
      # TODO optional get a valid version from the remote repo and roll to that, if no tag
      #  e.g. wget -q https://registry.hub.docker.com/v1/repositories/debian/tags -O -  | sed -e 's/[][]//g' -e 's/"//g' -e 's/ //g' | tr '}' '\n'  | awk -F: '{print $3}'
      # note: all images are not on docker hub nor are they always on a docker hub compatible api

      task_response = update_applied && CNFManager.workload_resource_test(args, config) do |resource, container, _|
        namespace = resource["namespace"]
        test_passed = true
        valid_cnf_testsuite_yml = true
        Log.for(t.name).debug { "container: #{container}" }
        Log.for(t.name).debug { "container_names: #{container_names}" }
        #todo use skopeo to get the next and previous versions of the cnf image dynamically
        config_container = container_names.find{|x| x.name==container.as_h["name"]} if container_names
        Log.debug { "config_container: #{config_container}" }
        unless config_container && !config_container.get_container_tag(tn).empty?
          puts "Please add the container name #{container.as_h["name"]} and a corresponding #{tn}_test_tag into your cnf-testsuite.yml under container names".colorize(:red)
          valid_cnf_testsuite_yml = false
        end

        Log.trace { "#{tn}: #{container} valid_cnf_testsuite_yml=#{valid_cnf_testsuite_yml}" }
        Log.trace { "#{tn}: #{container} config_container=#{config_container}" }
        if valid_cnf_testsuite_yml && config_container
          resp = KubectlClient::Utils.set_image(
            resource["kind"],
            resource["name"],
            container.as_h["name"].as_s,
            # split out image name from version tag
            container.as_h["image"].as_s.rpartition(":")[0],
            config_container.get_container_tag(tn),
            namespace: namespace
          )
        else
          resp = false
        end
        # If any containers dont have an update applied, fail
        test_passed = false if resp == false

        begin
          rollout_status = KubectlClient::Rollout.status(resource["kind"], resource["name"], namespace: namespace, timeout: "200s")
        rescue KubectlClient::ShellCMD::UnspecifiedError
        end

        unless rollout_status
          Log.info { "Rollout failed for #{resource["kind"]}/#{resource["name"]} in #{namespace} namespace" }
          test_passed = false
        end
        Log.trace { "#{tn}: #{container} test_passed=#{test_passed}" }
        test_passed
      end
      Log.trace { "#{tn}: task_response=#{task_response}" }
      if task_response
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "CNF for #{pretty_test_name_capitalized} Passed")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF for #{pretty_test_name_capitalized} Failed")
      end
      # TODO should we roll the image back to original version in an ensure?
      # TODO Use the kubectl rollback to history command
    end
  end
end

desc "Test if the CNF can perform a rollback"
task "rollback" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    container_names = config.common.container_names
    Log.for(t.name).debug { "container_names: #{container_names}" }

    update_applied = true
    rollout_status = true
    rollback_status = true
    version_change_applied = true

    unless container_names
      stdout_failure("Please add a container names set of entries into your cnf-testsuite.yml")
      next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF Rollback Failed")
    end

    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _|
      resource_kind = resource["kind"]
      resource_name = resource["name"]
      namespace = resource["namespace"]
      container_name = container.as_h["name"].as_s
      full_image_name_tag = container.as_h["image"].as_s.rpartition(":")
      image_name = full_image_name_tag[0]
      image_tag = full_image_name_tag[2]

      Log.for(t.name).debug {
        "Rollback: setting new version; resource=#{resource_kind}/#{resource_name}; container_name=#{container_name}; image_name=#{image_name}; image_tag: #{image_tag}"
      }
      #do_update = `kubectl set image deployment/coredns-coredns coredns=coredns/coredns:latest --record`

      version_change_applied = true
      # compare cnf_testsuite.yml container list with the current container name
      config_container = container_names.find{|x| x.name == container_name } if container_names
      unless config_container && !config_container.get_container_tag("rollback_from").empty?
        stdout_failure("Please add the container name #{container_name} and a corresponding rollback_from_tag into your cnf-testsuite.yml under container names")
        next false
      end

      rollback_from_tag = config_container.get_container_tag("rollback_from")
      if rollback_from_tag == image_tag
        stdout_failure("Rollback not possible. Please specify a different version than the helm chart default image.tag for 'rollback_from_tag' ")
        next false
      end

      Log.for(t.name).debug {
        "rollback: update #{resource_kind}/#{resource_name}, container: #{container_name}, image: #{image_name}, tag: #{rollback_from_tag}"
      }

      version_change_applied = KubectlClient::Utils.set_image(
        resource_kind,
        resource_name,
        container_name,
        image_name,
        rollback_from_tag,
        namespace: namespace
      )[:status].success?
      Log.for(t.name).info { "rollback version change successful? #{version_change_applied}" }

      rollout_status = KubectlClient::Rollout.status(resource_kind, resource_name, namespace: namespace, timeout: "180s")
      stdout_failure("Rollback failed on resource: #{resource_kind}/#{resource_name} and container: #{container_name}") unless rollout_status

      Log.for(t.name).debug { "rollback: rolling back to old version" }
      rollback_status = KubectlClient::Rollout.undo(resource_kind, resource_name, namespace: namespace)[:status].success?

      version_change_applied && rollout_status && rollback_status
    end

    if task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "CNF Rollback Passed")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF Rollback Failed")
    end
  end
end

desc "Test increasing/decreasing capacity"
task "increase_decrease_capacity" do |t, args|

  CNFManager::Task.task_runner(args, task: t) do |args, config|
    increase_test_base_replicas = "1"
    increase_test_target_replicas = "3"

    decrease_test_base_replicas = "3"
    decrease_test_target_replicas = "1"

    # TODO scale replicatsets separately
    # https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/#scaling-a-replicaset
    # resource["kind"].as_s.downcase == "replicaset"
    increase_task_response = CNFManager.cnf_workload_resources(args, config) do | resource|
      if resource["kind"].as_s.downcase == "deployment" ||
          resource["kind"].as_s.downcase == "statefulset"
        final_count = change_capacity(increase_test_base_replicas, increase_test_target_replicas, args, config, resource)
        increase_test_target_replicas == final_count
      else
        true
      end
    end
    increase_task_successful = increase_task_response.none?(false)

    if increase_task_successful
      decrease_task_response = CNFManager.cnf_workload_resources(args, config) do | resource|
        # TODO scale replicatsets separately
        # https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/#scaling-a-replicaset
        # resource["kind"].as_s.downcase == "replicaset"
        if resource["kind"].as_s.downcase == "deployment" ||
            resource["kind"].as_s.downcase == "statefulset"
          final_count = change_capacity(decrease_test_base_replicas, decrease_test_target_replicas, args, config, resource)
          decrease_test_target_replicas == final_count
        else
          true
        end
      end
    end
    decrease_task_successful = !decrease_task_response.nil? && decrease_task_response.none?(false)

    if increase_task_successful && decrease_task_successful
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Replicas increased to #{increase_test_target_replicas} and decreased to #{decrease_test_target_replicas}")
    else
      stdout_failure(increase_decrease_remedy_msg())
      unless increase_task_successful
        stdout_failure("Failed to increase replicas from #{increase_test_base_replicas} to #{increase_test_target_replicas}")
      else
        stdout_failure("Failed to decrease replicas from #{decrease_test_base_replicas} to #{decrease_test_target_replicas}")
      end  
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Capacity change failed")
    end
  end
end


def increase_decrease_remedy_msg()
<<-TEMPLATE

Replica failure can be due to insufficent permissions, image pull errors and other issues.
Learn more on remediation by viewing our USAGE.md doc at https://bit.ly/capacity_remedy
TEMPLATE
end

# desc "Test increasing capacity by setting replicas to 1 and then increasing to 3"
# task "increase_capacity" do |_, args|
#   CNFManager::Task.task_runner(args) do |args, config|
#     Log.debug { "increase_capacity" }
#     emoji_increase_capacity="📦📈"

#     target_replicas = "3"
#     base_replicas = "1"
#     # TODO scale replicatsets separately
#     # https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/#scaling-a-replicaset
#     # resource["kind"].as_s.downcase == "replicaset"
#     task_response = CNFManager.cnf_workload_resources(args, config) do | resource|
#       if resource["kind"].as_s.downcase == "deployment" ||
#           resource["kind"].as_s.downcase == "statefulset"
#         final_count = change_capacity(base_replicas, target_replicas, args, config, resource)
#         target_replicas == final_count
#       else
#         true
#       end
#     end
#     # if target_replicas == final_count 
#     if task_response.none?(false) 
#       upsert_passed_task("increase_capacity", "✔️  PASSED: Replicas increased to #{target_replicas} #{emoji_increase_capacity}")
#     else
#       upsert_failed_task(testsuite_task, increase_decrease_capacity_failure_msg(target_replicas, emoji_increase_capacity))
#     end
#   end
# end

# desc "Test decrease capacity by setting replicas to 3 and then decreasing to 1"
# task "decrease_capacity" do |_, args|
#   hi = CNFManager::Task.task_runner(args) do |args, config|
#     Log.debug { "decrease_capacity" }
#     target_replicas = "1"
#     base_replicas = "3"
#     task_response = CNFManager.cnf_workload_resources(args, config) do | resource|
#       # TODO scale replicatsets separately
#       # https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/#scaling-a-replicaset
#       # resource["kind"].as_s.downcase == "replicaset"
#       if resource["kind"].as_s.downcase == "deployment" ||
#           resource["kind"].as_s.downcase == "statefulset"
#         final_count = change_capacity(base_replicas, target_replicas, args, config, resource)
#         target_replicas == final_count
#       else
#         true
#       end
#     end
#     emoji_decrease_capacity="📦📉"

#     # if target_replicas == final_count 
#     if task_response.none?(false) 
#       ret = upsert_passed_task("decrease_capacity", "✔️  PASSED: Replicas decreased to #{target_replicas} #{emoji_decrease_capacity}")
#     else
#       ret = upsert_failed_task(testsuite_task, increase_decrease_capacity_failure_msg(target_replicas, emoji_decrease_capacity))
#     end
#     puts "1 ret: #{ret}"
#     ret
#   end
#   puts "hi: #{hi}"
# end


def change_capacity(base_replicas, target_replica_count, args, config, resource = {kind: "", 
                                                                                   metadata: {name: ""}})

  Log.for("change_capacity:resource").info { "#{resource["kind"]}/#{resource["metadata"]["name"]}; namespace: #{resource["metadata"]["namespace"]}" }
  Log.for("change_capacity:capacity").info { "Base replicas: #{base_replicas}; Target replicas: #{target_replica_count}" }

  Log.trace { "increase_capacity args.raw: #{args.raw}" }
  Log.trace { "increase_capacity args.named: #{args.named}" }

  initialization_time = base_replicas.to_i * 10
  KubectlClient::Utils.scale("#{resource["kind"]}", "#{resource["metadata"]["name"]}", base_replicas.to_i, resource.dig("metadata", "namespace").as_s)
  initialized_count = wait_for_scaling(resource, base_replicas, args)
  if initialized_count != base_replicas
    Log.debug { "#{resource["kind"]} initialized to #{initialized_count} and could not be set to #{base_replicas}" }
  else
    Log.debug { "#{resource["kind"]} initialized to #{initialized_count}" }
  end

  KubectlClient::Utils.scale("#{resource["kind"]}", "#{resource["metadata"]["name"]}", target_replica_count.to_i, resource.dig("metadata", "namespace").as_s)
  current_replicas = wait_for_scaling(resource, target_replica_count, args)

  current_replicas
end

def wait_for_scaling(resource, target_replica_count, args)
  Log.debug { "target_replica_count: #{target_replica_count}" }
  replicas_cmd = "kubectl get #{resource["kind"]} #{resource["metadata"]["name"]} -o=jsonpath='{.status.readyReplicas}'"

  namespace = resource.dig("metadata", "namespace")
  replicas_cmd = "#{replicas_cmd} -n #{namespace}"
  Process.run(
    replicas_cmd,
    shell: true,
    output: replicas_stdout = IO::Memory.new,
    error: replicas_stderr = IO::Memory.new
  )
  current_replicas = replicas_stdout.to_s.empty? ? "0" : replicas_stdout.to_s
  previous_replicas = current_replicas
  repeat_with_timeout(timeout: GENERIC_OPERATION_TIMEOUT, errormsg: "Pod scaling has timed-out", reset_on_nil: true) do
    Log.debug { "current_replicas before get #{resource["kind"]}: #{current_replicas}" }
    Log.trace { "$KUBECONFIG = #{ENV.fetch("KUBECONFIG", nil)}" }

    Process.run(
      replicas_cmd,
      shell: true,
      output: replicas_stdout = IO::Memory.new,
      error: replicas_stderr = IO::Memory.new
    )
    current_replicas = replicas_stdout.to_s.empty? ? "0" : replicas_stdout.to_s
    if current_replicas.to_i != previous_replicas.to_i
      previous_replicas = current_replicas
      next nil
    end
    current_replicas == target_replica_count
  end
  current_replicas
end

def extract_f_flags(helm_values : String?) : String?
  return nil unless helm_values

  # Regex to match each occurrence of `-f somefile.yaml`
  regex = /(-f\s+[^\s]+)/

  f_flags = [] of String
  offset = 0

  # Loop over matches; each capture group (match[1]) is a separate "-f <files>" substring
  while match = regex.match(helm_values, offset)
    f_flags << match[1]
    offset = match.end(0)
  end

  # Return `nil` if none found, otherwise a single joined string
  f_flags.empty? ? nil : f_flags.join(" ")
end

desc "Will the CNF install using helm with helm_deploy?"
task "helm_deploy" do |t, args|
  Log.for(t.name).debug { "helm_deploy args: #{args.inspect}" }

  CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config|
    if check_cnf_config(args) || CNFManager.cnf_installed?
      helm_used = !config.deployments.helm_charts.empty? || !config.deployments.helm_dirs.empty?

      if helm_used
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "CNF is installed via helm")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF has deployments that are not installed with helm")
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "No cnf_testsuite.yml found! Did you run the \"cnf_install\" task?")
    end
  end
end

task "helm_chart_published", ["setup:helm_local_install"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    helm = Helm::BinarySingleton.helm

    # Store chart search commands in an array
    chart_searches = [] of String

    # Collect helm chart search queries from deployments
    config.deployments.helm_charts.each do |deployment|
      helm_repo_name = deployment.helm_repo_name
      helm_chart_name = deployment.helm_chart_name

      helm_chart_full_name = "#{helm_repo_name}/#{helm_chart_name}"
      chart_searches << helm_chart_full_name
    end

    # Initialize flags to track the state of the task
    charts_found = !chart_searches.empty?
    all_published = true

    # Process the helm chart searches and log results for each search
    chart_searches.each do |helm_chart_full_name|
      helm_search_cmd = "#{helm} search repo #{helm_chart_full_name}"
      helm_search_status = Process.run(helm_search_cmd, shell: true, output: helm_search_stdout = IO::Memory.new, error: helm_search_stderr = IO::Memory.new)
      helm_search_output = helm_search_stdout.to_s
      Log.for(t.name).info { "Searching Helm chart: #{helm_chart_full_name}" }
      Log.for(t.name).info { "Helm search output:\n#{helm_search_output}" }

      # Check if the chart was found
      if helm_search_output =~ /No results found/
        all_published = false
      end
    end

    # Handle the case where no charts were specified
    unless charts_found
      Log.for(t.name).info { "No Helm charts found for searching." }
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "No Helm charts found to search")
    else
      # Return appropriate results based on search outcomes
      if all_published
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "All Helm charts are published")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "One or more Helm charts are not published")
      end
    end
  end
end

task "helm_chart_valid", ["setup:helm_local_install"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    current_dir = FileUtils.pwd
    helm = Helm::BinarySingleton.helm
    Log.info { "Current directory: #{current_dir}" }

    # Store chart locations and helm values
    chart_info = [] of Tuple(String, String, String?)

    # Collect helm chart paths and their values
    config.deployments.helm_charts.each do |deployment|
      chart_info << {
        File.join(current_dir, DEPLOYMENTS_DIR, deployment.name, deployment.helm_chart_name),
        deployment.name,
        deployment.helm_values
      }
    end

    # Collect helm directory paths and their values
    config.deployments.helm_dirs.each do |deployment|
      chart_info << {
        File.join(current_dir, DEPLOYMENTS_DIR, deployment.name, deployment.helm_directory),
        deployment.name,
        deployment.helm_values
      }
    end

    # Initialize flags to track the task state
    charts_found = !chart_info.empty?
    all_passed = true

    # Iterate over chart directories and store the results for each lint
    chart_info.each do |chart_dir, deployment_name, helm_values|
      # Extract any `-f <files>` occurrences
      f_flags = extract_f_flags(helm_values)
      helm_lint_cmd = if f_flags
        "#{helm} lint #{chart_dir} #{f_flags}"
      else
        "#{helm} lint #{chart_dir}"
      end

      Log.for(t.name).info { "Linting helm chart for deployment: #{deployment_name}" }
      Log.for(t.name).info { "Helm lint command: #{helm_lint_cmd}" }

      helm_lint_status = Process.run(helm_lint_cmd, shell: true, output: helm_lint_stdout = IO::Memory.new, error: helm_lint_stderr = IO::Memory.new)
      helm_lint_output = helm_lint_stdout.to_s

      Log.for(t.name).info { "Helm Lint output:\n#{helm_lint_output}" }

      # If the linting failed, mark as failed
      if !helm_lint_status.success?
        all_passed = false
      end
    end

    # Handle case where no charts were found
    unless charts_found
      Log.for(t.name).info { "No Helm charts or directories found for linting." }
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "No Helm charts found to lint")
    else
      # Return appropriate results based on linting outcomes
      if all_passed
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "Helm chart lint passed on all charts")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Helm chart lint failed on one or more charts")
      end
    end
  end
end


def setup_calico_cluster(cluster_name : String) : KindManager::Cluster
  Log.info { "Running cni_compatible(Cluster Creation)" }
  Helm.helm_repo_add("projectcalico","https://docs.projectcalico.org/charts")
  calico_cluster = KindManager.create_cluster_with_chart_and_wait(
    cluster_name,
    KindManager.disable_cni_config,
    "projectcalico/tigera-operator --version v3.20.2"
  )

  return calico_cluster
end

def setup_cilium_cluster(cluster_name : String) : KindManager::Cluster
  chart_opts = [
    "--set operator.replicas=1",
    "--set image.repository=cilium/cilium",
    "--set image.useDigest=false",
    "--set operator.image.useDigest=false",
    "--set operator.image.repository=cilium/operator"
  ]

  kind_manager = KindManager.new
  cluster = kind_manager.create_cluster(cluster_name, KindManager.disable_cni_config)
  Helm.helm_repo_add("cilium","https://helm.cilium.io/")
  chart = "cilium/cilium"
  chart_opts.push("--version 1.15.4")
  with_kubeconfig(cluster.kubeconfig) { Helm.install("#{cluster_name}-plugin", "#{chart}", namespace: "kube-system", values: "#{chart_opts.join(" ")}") }

  cluster.wait_until_pods_ready()
  Log.info { "cilium kubeconfig: #{cluster.kubeconfig}" }
  return cluster
end

desc "CNFs should work with any Certified Kubernetes product and any CNI-compatible network that meet their functionality requirements."
task "cni_compatible" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
     # TODO (kosstennbl) adapt cnf_to_new_cluster metod to new installation process. Until then - test is disabled. More info: #2153
    next CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "cni_compatible test was temporarily disabled, check #2153")
    docker_version = DockerClient.version_info()
    if docker_version.installed?
      ensure_kubeconfig!
      kubeconfig_orig = ENV["KUBECONFIG"]
      begin
        calico_cluster = setup_calico_cluster("calico-test")
        Log.info { "calico kubeconfig: #{calico_cluster.kubeconfig}" }
        calico_cnf_passed = CNFManager.cnf_to_new_cluster(config, calico_cluster.kubeconfig)
        Log.info { "calico_cnf_passed: #{calico_cnf_passed}" }
        puts "CNF failed to install on Calico CNI cluster".colorize(:red) unless calico_cnf_passed

        cilium_cluster = setup_cilium_cluster("cilium-test")
        cilium_cnf_passed = CNFManager.cnf_to_new_cluster(config, cilium_cluster.kubeconfig)
        Log.info { "cilium_cnf_passed: #{cilium_cnf_passed}" }
        puts "CNF failed to install on Cilium CNI cluster".colorize(:red) unless cilium_cnf_passed

        if calico_cnf_passed && cilium_cnf_passed
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "CNF compatible with both Calico and Cilium")
        else
          CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF not compatible with either Calico or Cilium")
        end
      ensure
        kind_manager = KindManager.new
        kind_manager.delete_cluster("calico-test")
        kind_manager.delete_cluster("cilium-test")
        ENV["KUBECONFIG"]="#{kubeconfig_orig}"
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "Docker not installed")
    end
  end
end

desc "CNF should not use any deprecated Kubernetes features"
task "deprecated_k8s_features" do |t, args|
  logger = WLOG.for("deprecated_k8s_features")
  logger.info { "Testing CNF for usage of deprecated Kubernetes features" }

  CNFManager::Task.task_runner(args, task: t) do |args, config|
    skipped = false
    passed = false

    unless File.exists?(CNF_INSTALL_LOG_FILE)
      logger.warn { "Installation log file not found, should be in: #{CNF_INSTALL_LOG_FILE}" }
      skipped = true
    end

    unless skipped
      pattern = /deprecated/
      warnings = [] of String
      File.each_line(CNF_INSTALL_LOG_FILE) { |line| warnings << line if pattern.match(line) }
      logger.info { "Found #{warnings.size} deprecated feature warnings" }

      if warnings.empty?
        passed = true
        logger.info { "CNF does not use any deprecated features" }
      else
        stdout_warning("Deprecated features warnings:\n#{warnings.join("\n")}")
        logger.info { "Warnings:\n#{warnings.join("\n")}" }
        passed = false
      end
    end

    if skipped
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "CNF installation log file not found")
    elsif passed
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "CNF does not use deprecated K8s features")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF uses deprecated K8s features")
    end
  end
end
