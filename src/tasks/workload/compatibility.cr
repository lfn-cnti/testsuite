# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../../modules/docker_client"
require "../utils/utils.cr"


desc "The CNF test suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s kubectl"
category_task "compatibility", ["helm_chart_valid", "helm_chart_published", "helm_deploy", "cni_compatible", "increase_decrease_capacity", "rollback", "deprecated_k8s_features"].concat(ROLLING_VERSION_CHANGE_TEST_NAMES),
  title: "Compatibility, Installability, and Upgradeability"
ROLLING_VERSION_CHANGE_TEST_NAMES.each do |tn|
  pretty_test_name = tn.split(/:|_/).join(" ")
  pretty_test_name_capitalized = tn.split(/:|_/).map(&.capitalize).join(" ")

  desc "Test if the CNF containers are loosely coupled by performing a #{pretty_test_name}"
  scored_task "#{tn}" do |t, args|
    CNFManager::Task.task_runner(args, task: t) do |args, config, result|
      container_names = config.common.container_names
      Log.for(t.name).debug { "container_names: #{container_names}" }
      rolled = 0
      unconfigured = 0

      # TODO use tag associated with image name string (e.g. busybox:v1.7.9) as the version tag
      # TODO optional get a valid version from the remote repo and roll to that, if no tag
      #  e.g. wget -q https://registry.hub.docker.com/v1/repositories/debian/tags -O -  | sed -e 's/[][]//g' -e 's/"//g' -e 's/ //g' | tr '}' '\n'  | awk -F: '{print $3}'
      # note: all images are not on docker hub nor are they always on a docker hub compatible api

      task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _|
        namespace = resource["namespace"]
        container_name = container.as_h["name"].as_s
        test_passed = true
        Log.for(t.name).debug { "container: #{container}" }
        #todo use skopeo to get the next and previous versions of the cnf image dynamically
        config_container = container_names.find{|x| x.name == container_name} if container_names
        Log.debug { "config_container: #{config_container}" }

        # A container without the tag this test needs is a configuration gap,
        # not a rollout failure: it is left out with the remediation, and the
        # test is skipped when no container had one (#2577).
        unless config_container && !config_container.get_container_tag(tn).empty?
          result.append_remediation("Please add the container name #{container_name} and a corresponding #{tn}_test_tag into your cnti-testsuite.yaml under container names")
          unconfigured += 1
          next true
        end
        rolled += 1

        # split out image name from version tag
        image_name = container.as_h["image"].as_s.rpartition(":")[0]
        tag = config_container.get_container_tag(tn)
        resp = KubectlClient::Utils.set_image(resource["kind"], resource["name"], container_name, image_name, tag, namespace: namespace)
        unless resp[:status].success?
          result.add_impacted_resource(resource["kind"], resource["name"], namespace, container: container_name,
            reason: "could not set image #{image_name}:#{tag}: #{resp[:error].to_s.strip}")
          next false
        end

        rollout_error = nil
        begin
          rollout_status = KubectlClient::Rollout.status(resource["kind"], resource["name"], namespace: namespace, timeout: "200s")
        rescue ex : KubectlClient::ShellCMD::UnspecifiedError
          rollout_error = ex.message.to_s.lines.first?
        end

        unless rollout_status
          Log.info { "Rollout failed for #{resource["kind"]}/#{resource["name"]} in #{namespace} namespace" }
          result.add_impacted_resource(resource["kind"], resource["name"], namespace, container: container_name,
            reason: "rollout to #{image_name}:#{tag} did not complete within 200s#{rollout_error ? ": #{rollout_error}" : ""}")
          test_passed = false
        end
        Log.trace { "#{tn}: #{container} test_passed=#{test_passed}" }
        test_passed
      end
      Log.trace { "#{tn}: task_response=#{task_response}" }
      if rolled == 0 && unconfigured > 0
        result.skipped("No #{tn}_test_tag configured for any container: add container_names with a #{tn}_test_tag to cnti-testsuite.yaml")
      elsif task_response
        result.passed("CNF for #{pretty_test_name_capitalized} Passed")
      else
        result.failed("CNF for #{pretty_test_name_capitalized} Failed")
      end
      # TODO should we roll the image back to original version in an ensure?
      # TODO Use the kubectl rollback to history command
    end
  end
end

desc "Test if the CNF can perform a rollback"
scored_task "rollback" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    container_names = config.common.container_names
    Log.for(t.name).debug { "container_names: #{container_names}" }

    rolled = 0
    unconfigured = 0

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

      # A container without a usable rollback_from_tag is a configuration gap,
      # not a rollback failure: it is left out with the remediation, and the
      # test is skipped when no container had one (#2577).
      config_container = container_names.find{|x| x.name == container_name } if container_names
      unless config_container && !config_container.get_container_tag("rollback_from").empty?
        result.append_remediation("Please add the container name #{container_name} and a corresponding rollback_from_tag into your cnti-testsuite.yaml under container names")
        unconfigured += 1
        next true
      end

      rollback_from_tag = config_container.get_container_tag("rollback_from")
      if rollback_from_tag == image_tag
        result.append_remediation("Rollback not possible for #{container_name}: rollback_from_tag equals the installed tag #{image_tag}; specify a different version")
        unconfigured += 1
        next true
      end
      rolled += 1

      Log.for(t.name).debug {
        "rollback: update #{resource_kind}/#{resource_name}, container: #{container_name}, image: #{image_name}, tag: #{rollback_from_tag}"
      }

      resp = KubectlClient::Utils.set_image(resource_kind, resource_name, container_name, image_name, rollback_from_tag, namespace: namespace)
      unless resp[:status].success?
        result.add_impacted_resource(resource_kind, resource_name, namespace, container: container_name,
          reason: "could not set image #{image_name}:#{rollback_from_tag}: #{resp[:error].to_s.strip}")
        next false
      end

      rollout_error = nil
      begin
        rollout_status = KubectlClient::Rollout.status(resource_kind, resource_name, namespace: namespace, timeout: "180s")
      rescue ex : KubectlClient::ShellCMD::UnspecifiedError
        rollout_error = ex.message.to_s.lines.first?
      end
      unless rollout_status
        result.add_impacted_resource(resource_kind, resource_name, namespace, container: container_name,
          reason: "rollout to #{image_name}:#{rollback_from_tag} did not complete within 180s#{rollout_error ? ": #{rollout_error}" : ""}")
      end

      Log.for(t.name).debug { "rollback: rolling back to old version" }
      undo = KubectlClient::Rollout.undo(resource_kind, resource_name, namespace: namespace)
      unless undo[:status].success?
        result.add_impacted_resource(resource_kind, resource_name, namespace, container: container_name,
          reason: "rollout undo failed: #{undo[:error].to_s.strip}")
      end

      !rollout_status.nil? && undo[:status].success?
    end

    if rolled == 0 && unconfigured > 0
      result.skipped("No usable rollback_from_tag configured for any container: add container_names with a rollback_from_tag to cnti-testsuite.yaml")
    elsif task_response
      result.passed("CNF Rollback Passed")
    else
      result.failed("CNF Rollback Failed")
    end
  end
end

desc "Test increasing/decreasing capacity"
scored_task "increase_decrease_capacity",
  type: CNFManager::TestType::Essential,
  emoji: "📦📈📉" do |t, args|

  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Each scalable resource starts from the replica count it was deployed
    # with, is scaled up by this much, then back to that count - so the test
    # proves both directions and leaves the CNF as it found it.
    increase_by = 2

    # Everything scaled, with the count to return it to; restored in `ensure`
    # whatever happens in between, so a failure here never changes what the
    # tests after this one see.
    deployed = {} of Tuple(String, String, String) => Int32
    failures = [] of String
    # Workloads an operator owns take their size from its custom resource.
    # They are scaled like the others, and many follow; one that does not has
    # its operator to answer to (it reverts the change, or never configures
    # pods it did not ask for), so it is named, not held against the CNF.
    operator_owned = [] of String
    # Workloads deployed with no replicas (arbiters, standby sets) run nothing
    # to scale; they are named in the details, not scaled.
    idle = [] of String

    begin
      CNFManager.cnf_workload_resources(args, config) do |resource|
        kind = resource["kind"].as_s.downcase
        next unless kind == "deployment" || kind == "statefulset"
        name = resource["metadata"]["name"].as_s
        namespace = resource.dig("metadata", "namespace").as_s
        ref = "#{resource["kind"].as_s}/#{name}"

        replicas = deployed_replicas(resource["kind"].as_s, name, namespace)
        if replicas == 0
          idle << "#{ref} in #{namespace}: deployed with 0 replicas, not scaled"
          next
        end
        owner = custom_resource_controller(KubectlClient::Get.resource(resource["kind"].as_s, name, namespace))
        deployed[{resource["kind"].as_s, name, namespace}] = replicas
        target = replicas + increase_by
        Log.for(t.name).info { "#{ref} in #{namespace}: deployed with #{replicas} replicas; scaling to #{target}, then back" }

        ready = scale_and_wait(resource, target, args)
        if ready != target.to_s && owner
          operator_owned << "#{ref} in #{namespace}: owned by #{owner}, which sets its replica count; a direct scale to #{target} did not take (#{ready} ready), so it is not counted"
          next
        end
        if ready != target.to_s
          failures << "#{ref} in #{namespace}: increase from #{replicas} to #{target} replicas did not complete (#{ready} ready)"
          why = WorkloadDiagnostics.report(result, resource["kind"].as_s, name, namespace, "#{ref} while scaling to #{target}")
          result.add_impacted_resource(resource["kind"].as_s, name, namespace,
            reason: "could not scale up to #{target} replicas (#{ready} ready)#{why.first?.try { |w| ": #{w}" }}")
          next
        end

        ready = scale_and_wait(resource, replicas, args)
        if ready != replicas.to_s
          failures << "#{ref} in #{namespace}: decrease from #{target} back to #{replicas} replicas did not complete (#{ready} ready)"
          why = WorkloadDiagnostics.report(result, resource["kind"].as_s, name, namespace, "#{ref} while scaling back to #{replicas}")
          result.add_impacted_resource(resource["kind"].as_s, name, namespace,
            reason: "could not scale back down to #{replicas} replicas (#{ready} ready)#{why.first?.try { |w| ": #{w}" }}")
        end
      end
    ensure
      deployed.each do |(kind, name, namespace), replicas|
        KubectlClient::Utils.scale(kind, name, replicas, namespace)
      end
    end

    idle.each { |line| result.append_description(line) }
    operator_owned.each { |line| result.append_description(line) }
    if deployed.empty? && !idle.empty?
      result.na("increase_decrease_capacity not applicable: no Deployment or StatefulSet runs pods to scale")
    elsif !deployed.empty? && operator_owned.size == deployed.size
      result.na("increase_decrease_capacity not applicable: every workload is sized by an operator's custom resource and none followed a direct scale")
    elsif deployed.empty?
      result.skipped("No Deployment or StatefulSet to scale")
    elsif failures.empty?
      result.passed("Replicas increased to deployed count + #{increase_by} and decreased back for #{deployed.size - operator_owned.size} resource(s)")
    else
      failures.each { |failure| result.append_description(failure) }
      result.append_remediation(increase_decrease_remedy_msg())
      result.failed("Capacity change failed")
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


# The replica count a resource was deployed with: its live spec, defaulting
# to Kubernetes' own default of 1 when the field is unset.
# The workload's controller owner, as "Kind/name", when it is a custom
# resource (an API group other than the core, apps and batch ones): an
# operator's object, not a Kubernetes controller. Nil otherwise.
def custom_resource_controller(workload : JSON::Any) : String?
  controller = workload.dig?("metadata", "ownerReferences").try(&.as_a?).try &.find { |ref| ref["controller"]?.try(&.as_bool?) }
  return nil unless controller
  api_version = controller["apiVersion"]?.try(&.as_s?) || ""
  group = api_version.includes?('/') ? api_version.split('/').first : ""
  return nil if ["", "apps", "batch"].includes?(group)
  "#{controller["kind"]?.try(&.as_s?)}/#{controller["name"]?.try(&.as_s?)}"
end

def deployed_replicas(kind : String, name : String, namespace : String) : Int32
  KubectlClient::Get.resource(kind, name, namespace).dig?("spec", "replicas").try(&.as_i) || 1
end

# Scales the resource and returns the ready replica count once it settles.
def scale_and_wait(resource, target : Int32, args) : String
  Log.for("scale_and_wait").info { "#{resource["kind"]}/#{resource["metadata"]["name"]} in #{resource["metadata"]["namespace"]}: scaling to #{target}" }
  KubectlClient::Utils.scale("#{resource["kind"]}", "#{resource["metadata"]["name"]}", target, resource.dig("metadata", "namespace").as_s)
  wait_for_scaling(resource, target.to_s, args)
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
  # This waits for pods to become ready, so it gets the pod readiness budget
  # rather than the generic one: a replica that needs a minute to pass its
  # readiness probe on a busy node is what the budget is for. The timer resets
  # on every change of the ready count, so it bounds the gap between replicas.
  repeat_with_timeout(timeout: POD_READINESS_TIMEOUT, errormsg: "Pod scaling has timed-out", reset_on_nil: true) do
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

desc "Check that each Helm deployment of the CNF is installed as a Helm release"
scored_task "helm_deploy",
  emoji: "⚙🛠️⬆☁" do |t, args|
  CNFManager::Task.task_runner(args, task: t, check_cnf_installed: false) do |args, config, result|
    unless check_cnf_config(args) || CNFManager.cnf_installed?
      usage_error! "No cnti-testsuite.yaml found: run cnf_install first, or pass --cnf-config PATH."
    end

    # The verdict used to come from the config alone; it now comes from the
    # cluster: every Helm deployment must be a deployed Helm release under the
    # name and namespace the installer gave it (#2592).
    deployments = config.deployments.helm_charts.map { |d| {d.name, d.namespace} } +
                  config.deployments.helm_dirs.map { |d| {d.name, d.namespace} }
    if deployments.empty?
      result.na("CNF is installed from manifests, not from Helm charts")
      next
    end

    missing = 0
    deployments.each do |name, configured_namespace|
      namespace = configured_namespace.empty? ? DEFAULT_CNF_NAMESPACE : configured_namespace
      release = Helm.release_status(name, namespace)
      unless release
        result.add_impacted_resource("HelmRelease", name, namespace, reason: "no Helm release with this name")
        missing += 1
        next
      end
      chart = release["chart"]?.to_s
      app_version = release["app_version"]?.to_s
      status = release["status"]?.to_s
      result.append_description("release #{name} in #{namespace}: chart #{chart}#{app_version.empty? ? "" : " (app #{app_version})"}, status #{status}")
      unless status == "deployed"
        result.add_impacted_resource("HelmRelease", name, namespace, reason: "release status is #{status}, not deployed")
        missing += 1
      end
    end

    if missing == 0
      result.passed("Every Helm deployment of the CNF is a deployed Helm release (#{deployments.size})")
    else
      result.append_remediation("Install each Helm deployment with `helm install <name>` in its namespace; the suite's cnf_install does this from cnti-testsuite.yaml.")
      result.failed("#{missing} of #{deployments.size} Helm deployment(s) have no deployed Helm release")
    end
  end
end

desc "Checks if the CNF's helm chart is published in a helm repository"
scored_task "helm_chart_published",
  deps: ["setup:install_local_helm"],
  emoji: "⎈📦🌐" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    helm = Helm::Binary.get
    charts = config.deployments.helm_charts
    if charts.empty?
      result.na("The CNF has no Helm chart deployment; only charts can be published in a repository")
      next
    end

    # Every chart is reported with where it was looked for and what came
    # back; each one the repository does not know is a finding (#2598).
    unpublished = 0
    charts.each do |deployment|
      unless deployment.registry_url.empty?
        result.append_description("chart #{deployment.name}: pulled from OCI registry #{deployment.registry_url}")
        next
      end
      full_name = "#{deployment.helm_repo_name}/#{deployment.helm_chart_name}"
      status = Process.run("#{helm} search repo #{full_name}", shell: true, output: stdout = IO::Memory.new, error: stderr = IO::Memory.new)
      output = stdout.to_s
      Log.for(t.name).info { "helm search repo #{full_name}:\n#{output}#{stderr}" }
      versions = output.lines.select { |l| l.starts_with?("#{full_name}\t") || l.starts_with?("#{full_name} ") }
      if status.success? && !versions.empty?
        found = versions.first.split(/\t|\s{2,}/).map(&.strip).reject(&.empty?)
        result.append_description("chart #{deployment.name}: #{full_name} found in repository #{deployment.helm_repo_url} (chart version #{found[1]?}, app version #{found[2]?})")
      else
        unpublished += 1
        why = status.success? ? output.strip : stderr.to_s.strip
        why = "no results" if why.empty?
        result.append_description("chart #{deployment.name}: #{full_name} not found in repository #{deployment.helm_repo_url}: #{why}")
        result.add_impacted_resource("HelmChart", deployment.name, reason: "#{full_name} is not published in #{deployment.helm_repo_url}")
      end
    end

    if unpublished == 0
      result.passed("All Helm charts are published")
    else
      result.append_remediation("Publish the chart in a Helm repository (or an OCI registry) and reference it from there in cnti-testsuite.yaml, so users install a versioned, signed artifact instead of chart sources.")
      result.failed("#{unpublished} Helm chart(s) not published")
    end
  end
end

desc "Checks if the CNF's helm chart passes `helm lint`"
scored_task "helm_chart_valid",
  deps: ["setup:install_local_helm"],
  emoji: "⎈📝☑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    current_dir = FileUtils.pwd
    helm = Helm::Binary.get

    # Chart directory and values of every chart or chart directory deployment.
    chart_info = [] of Tuple(String, String, String?)
    config.deployments.helm_charts.each do |deployment|
      chart_info << {File.join(current_dir, DEPLOYMENTS_DIR, deployment.name, deployment.helm_chart_name), deployment.name, deployment.helm_values}
    end
    config.deployments.helm_dirs.each do |deployment|
      chart_info << {File.join(current_dir, DEPLOYMENTS_DIR, deployment.name, File.basename(deployment.helm_directory)), deployment.name, deployment.helm_values}
    end
    if chart_info.empty?
      result.na("The CNF has no Helm chart deployment; only charts can be linted")
      next
    end

    # Every chart's lint output goes to the details; a failing chart is a
    # finding with its first error as the reason (#2598).
    failing = 0
    chart_info.each do |chart_dir, deployment_name, helm_values|
      f_flags = extract_f_flags(helm_values.try { |v| CNFInstall.resolve_helm_values(v, CNFInstall.installed_config_dir) })
      helm_lint_cmd = f_flags ? "#{helm} lint #{chart_dir} #{f_flags}" : "#{helm} lint #{chart_dir}"
      Log.for(t.name).info { "Helm lint command: #{helm_lint_cmd}" }
      status = Process.run(helm_lint_cmd, shell: true, output: stdout = IO::Memory.new, error: stderr = IO::Memory.new)
      output = (stdout.to_s + stderr.to_s).strip
      Log.for(t.name).info { "Helm lint output:\n#{output}" }

      # Lines helm marks [ERROR] or [WARNING]; the "==> Linting" banner and
      # the closing tally say nothing a reader needs.
      findings = output.lines.map(&.strip).select { |l| l.starts_with?("[") }
      if status.success?
        result.append_description("chart #{deployment_name}: lint passed#{findings.empty? ? "" : " with " + findings.join("; ")}")
      else
        failing += 1
        errors = findings.select(&.starts_with?("[ERROR]"))
        first = errors.first? || output.lines.map(&.strip).reject(&.empty?).last? || "helm lint exited #{status.exit_code}"
        result.append_description("chart #{deployment_name}: lint failed: #{findings.empty? ? output : findings.join("; ")}")
        result.add_impacted_resource("HelmChart", deployment_name, reason: first)
      end
    end

    if failing == 0
      result.passed("Helm chart lint passed on all charts")
    else
      result.append_remediation("Fix the errors helm lint reports for each chart (run `helm lint <chart> [-f values]` locally) so the chart renders and validates before it is shipped.")
      result.failed("Helm chart lint failed on #{failing} chart(s)")
    end
  end
end


# Annotation Multus and other meta-CNIs use to request extra networks.
CNI_NETWORKS_ANNOTATION = "k8s.v1.cni.cncf.io/networks"
# Vendor-specific API groups / annotation prefixes that tie a CNF to one CNI plugin.
CNI_VENDOR_MARKERS = ["projectcalico.org", "cilium.io", "k8s.cni.cncf.io"]

desc "CNFs should work with any Certified Kubernetes product and any CNI-compatible network that meet their functionality requirements."
scored_task "cni_compatible",
  emoji: "🔓🔑" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    coupled = 0
    CNFManager.cnf_resources(args, config) do |resource|
      api_version = resource.dig?("apiVersion").try(&.as_s?) || ""
      kind = resource.dig?("kind").try(&.as_s?)
      name = resource.dig?("metadata", "name").try(&.as_s?)
      namespace = resource.dig?("metadata", "namespace").try(&.as_s?)
      next unless kind && name

      flag = ->(reason : String) do
        coupled += 1
        result.add_impacted_resource(kind, name, namespace, reason: reason)
        Log.for(t.name).info { "#{kind}/#{name}: #{reason}" }
      end

      if kind == "NetworkAttachmentDefinition"
        flag.call("requires a Multus NetworkAttachmentDefinition (#{api_version})")
      elsif (vendor = CNI_VENDOR_MARKERS.find { |m| api_version.includes?(m) })
        flag.call("uses the CNI-specific API #{api_version}")
      end

      # Pod-level annotations: on the pod itself or in a workload's pod template.
      [resource.dig?("metadata", "annotations"),
       resource.dig?("spec", "template", "metadata", "annotations")].each do |annotations|
        annotations.try(&.as_h?).try(&.each do |key, value|
          key = key.as_s? || next
          if key == CNI_NETWORKS_ANNOTATION
            flag.call("requests additional CNI networks: #{CNI_NETWORKS_ANNOTATION}=#{value}")
          elsif (vendor = CNI_VENDOR_MARKERS.find { |m| key.includes?(m) })
            flag.call("carries the CNI-specific annotation #{key}")
          end
        end)
      end

      # SR-IOV device resources requested by any container.
      [resource.dig?("spec", "containers"),
       resource.dig?("spec", "template", "spec", "containers")].each do |containers|
        containers.try(&.as_a?).try(&.each do |container|
          container_name = container.dig?("name").try(&.as_s?)
          ["requests", "limits"].each do |section|
            container.dig?("resources", section).try(&.as_h?).try(&.each_key do |key|
              key = key.as_s? || next
              if key.downcase.includes?("sriov")
                flag.call("container #{container_name} requests the SR-IOV device resource #{key}")
              end
            end)
          end
        end)
      end
    end

    if coupled.zero?
      result.passed("No coupling to a specific CNI plugin detected")
    else
      result.failed("CNF is coupled to specific CNI plugins or features")
    end
  end
end

desc "CNF should not use any deprecated Kubernetes features"
scored_task "deprecated_k8s_features" do |t, args|
  logger = WLOG.for("deprecated_k8s_features")
  logger.info { "Testing CNF for usage of deprecated Kubernetes features" }

  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    unless File.exists?(COMMON_MANIFEST_FILE_PATH)
      result.skipped("CNF manifest not found: #{COMMON_MANIFEST_FILE_PATH}; run cnf_install first")
      next
    end

    # The API server is the authority on what is deprecated: a server-side
    # dry-run of the CNF's composite manifest returns the same Warning headers
    # kubectl shows on install, for every resource whatever its install
    # method, without depending on a log file (#2578).
    #
    # Some warnings are only issued on create (the Ingress strategy warns
    # about kubernetes.io/ingress.class when the annotation is new, not when
    # an installed object is re-applied unchanged), so the manifest is
    # dry-run both as a create and as an apply and the warnings are joined.
    # A resource whose *name* contains "deprecated" is not a finding: the
    # word has to stand on its own in the warning.
    resp = KubectlClient::ShellCMD.run("kubectl apply --dry-run=server -f #{COMMON_MANIFEST_FILE_PATH}", logger)
    create = KubectlClient::ShellCMD.run("kubectl create --dry-run=server -f #{COMMON_MANIFEST_FILE_PATH}", logger)
    warnings = (resp[:error].lines + create[:error].lines).map(&.strip)
      .select { |line| line.starts_with?("Warning:") && line =~ /(?<![\w-])deprecated(?![\w-])/i }
      .map { |line| line.sub(/^Warning:\s*/, "") }
      .uniq
    logger.info { "Found #{warnings.size} deprecation warning(s)" }

    if warnings.empty? && !resp[:status].success?
      result.skipped("Could not dry-run the CNF manifest against the API server: #{resp[:error].lines.first?.to_s.strip}")
      next
    end

    if warnings.empty?
      result.passed("CNF does not use deprecated K8s features")
      next
    end

    # A warning names an API version and kind, or an annotation, never the
    # object; the manifest says which of the CNF's resources it belongs to.
    resources = CNFInstall::Manifest.manifest_path_to_ymls(COMMON_MANIFEST_FILE_PATH)
    warnings.each do |warning|
      result.append_description("Deprecated: #{warning}")
      matched = [] of YAML::Any
      if (m = warning.match(/^(\S+\/\S+) (\S+) is deprecated/))
        matched = resources.select { |r| r["apiVersion"]?.to_s == m[1] && r["kind"]?.to_s == m[2] }
      elsif (m = warning.match(/annotations?\W+"?([A-Za-z0-9.\/_-]+)"?/))
        matched = resources.select { |r| r.dig?("metadata", "annotations", m[1]) }
      end
      matched.each do |r|
        result.add_impacted_resource(r["kind"].to_s, r.dig("metadata", "name").to_s, r.dig?("metadata", "namespace").try(&.to_s), reason: warning)
      end
    end
    result.append_remediation("Move to the replacement named in each warning; the API server drops the deprecated version in the release the warning states.")
    result.failed("CNF uses deprecated K8s features")
  end
end
