# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../../modules/docker_client"
require "../utils/utils.cr"


desc "The CNF test suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s kubectl"
category_task "compatibility", ["helm_chart_valid", "helm_chart_published", "helm_deploy", "cni_compatible", "increase_decrease_capacity", "rollback", "deprecated_k8s_features", "dual_stack"].concat(ROLLING_VERSION_CHANGE_TEST_NAMES),
  title: "Compatibility, Installability, and Upgradeability"
ROLLING_VERSION_CHANGE_TEST_NAMES.each do |tn|
  pretty_test_name = tn.split(/:|_/).join(" ")
  pretty_test_name_capitalized = tn.split(/:|_/).map(&.capitalize).join(" ")

  desc "Test if the CNF containers are loosely coupled by performing a #{pretty_test_name}"
  scored_task "#{tn}",
    deps: ["setup:install_cluster_tools"] do |t, args|
    CNFManager::Task.task_runner(args, task: t) do |args, config, result|
      container_names = config.common.container_names
      Log.for(t.name).debug { "container_names: #{container_names}" }
      rolled = 0
      unconfigured = 0
      batch = Set(String).new
      # Workloads an operator owns take their image from its custom resource
      # (#2810): listed, not rolled, not counted.
      owned = Set(String).new
      # Every workload this test changes, with the deployed image of each
      # container it changed: put back after the test, pass or fail.
      changed = RolloutRestore::Changed.new
      restored = true
      task_response = false
      # Charts from a repository or an OCI registry are moved as releases,
      # between the installed chart version and the one before it: image
      # and pod spec together, as an upgrade does (#2820). Their workloads
      # are judged by the release's move, not one image at a time.
      releases = ReleaseUpgrade.releases(config)
      release_workloads = releases.flat_map(&.workloads).to_set
      # Releases whose previous version could not be installed: no upgrade
      # to judge.
      unprepared = [] of String
      # Workloads rolled one image at a time whose previous image does not
      # start under the pod spec the current chart renders: version skew,
      # which no upgrade produces; named, not judged.
      skew = Set(String).new
      # Releases with no workload a move would roll out: not judged.
      idle = Set(String).new

      begin
        task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _, live|
          # A Job's pod template is immutable and runs once: nothing rolls.
          if CNFManager.batch_workload?(resource)
            CNFManager.batch_workload_listed?(resource, result, t.name) if batch.add?("#{resource[:kind]}/#{resource[:name]}/#{resource[:namespace]}")
            next true
          end
          next true if operator_owned_listed?(resource, live, owned, result)
          next true if release_workloads.includes?({resource[:kind], resource[:name], resource[:namespace]})
          namespace = resource["namespace"]
          container_name = container.as_h["name"].as_s
          test_passed = true
          Log.for(t.name).debug { "container: #{container}" }
          config_container = container_names.find{|x| x.name == container_name} if container_names
          Log.debug { "config_container: #{config_container}" }

          # The version to move to: the configured tag, else the image's
          # previous release (#2816). A container with neither is a
          # configuration gap, not a rollout failure: it is left out with the
          # remediation, and the test is skipped when no container had one
          # (#2577).
          configured_tag = config_container.try(&.get_container_tag(tn)) || ""
          tag = rollout_target_tag(result, configured_tag, "#{tn}_test_tag",
            "#{resource["kind"]}/#{resource["name"]} in #{namespace}", container_name, container.as_h["image"].as_s)
          unless tag
            unconfigured += 1
            next true
          end
          rolled += 1

          # split out image name from version tag
          image_name = container.as_h["image"].as_s.rpartition(":")[0]
          key = {resource["kind"], resource["name"], namespace}
          deployed = changed[key]? || begin
            images = {} of String => String
            changed[key] = images
            # A stop while the image is changed puts the deployed images back (#2713).
            RunStop.register(RolloutRestore.stop_key(*key)) { RolloutRestore.set_back(*key, images) }
            images
          end
          deployed[container_name] ||= container.as_h["image"].as_s
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
            # Why: the pods that are not Ready, the cluster's Warning events and
            # their last log lines, with the first reason in the finding.
            why = WorkloadDiagnostics.report(result, resource["kind"], resource["name"], namespace,
              "#{resource["kind"]}/#{resource["name"]} during the #{pretty_test_name} to #{image_name}:#{tag}")
            if skew_line = version_skew(configured_tag, why)
              rolled -= 1
              skew << "#{resource["kind"]}/#{resource["name"]} in #{namespace}"
              result.append_description("#{resource["kind"]}/#{resource["name"]} in #{namespace}, container #{container_name}: version skew, #{image_name}:#{tag} (the release before the deployed one) does not start under the pod spec the current chart renders (#{skew_line}); not judged, since an upgrade moves image and spec together and there is no previous release of the chart to upgrade from")
              next true
            end
            result.add_impacted_resource(resource["kind"], resource["name"], namespace, container: container_name,
              reason: "rollout to #{image_name}:#{tag} did not complete within 200s#{rollout_error ? ": #{rollout_error}" : ""}#{why.first?.try { |w| "; #{w}" }}")
            test_passed = false
          end
          Log.trace { "#{tn}: #{container} test_passed=#{test_passed}" }
          test_passed
        end

        releases.each do |release|
          if release.workloads.empty?
            # Nothing a move would roll out: not judged, as for a Job.
            idle << release.name
            result.append_description("#{release.label}: no Deployment, StatefulSet or DaemonSet of the release to roll out; not judged")
            next
          end
          previous = ReleaseUpgrade.previous_version(release, result)
          unless previous
            unconfigured += 1
            next
          end
          # The downgrade is the judged move; the update is judged on the way
          # back, from the release before to the one under test.
          legs = tn == "rolling_downgrade" ? [{previous, true}] : [{previous, false}, {release.installed, true}]
          outcome = true
          legs.each do |(version, judged)|
            reason = ReleaseUpgrade.move(release, version, result, pretty_test_name, judged)
            next unless reason
            unless judged
              result.append_description("#{release.label}: the release before, #{version}, could not be installed, so there is no #{pretty_test_name} to judge: #{reason}")
              unprepared << release.name
              outcome = nil
              break
            end
            outcome = false
          end
          next if outcome.nil?
          rolled += 1
          task_response &&= outcome
          result.append_description("#{release.label}: #{legs.map { |(v, _)| v }.join(", then ")}: every workload of the release rolled out") if outcome
        end
      ensure
        # Back to the deployed images and releases, whatever happened above,
        # so the tests after this one start from the CNF as deployed.
        restored = RolloutRestore.restore(changed, result, tn)
        restored = ReleaseUpgrade.restore(releases, result, tn) && restored
      end
      Log.trace { "#{tn}: task_response=#{task_response}" }
      # A CNF that is not back as deployed fails, whatever was judged.
      if !restored
        result.failed("CNF for #{pretty_test_name_capitalized} Failed")
      elsif rolled == 0 && unconfigured == 0 && unprepared.empty? && !(batch.empty? && owned.empty? && skew.empty? && idle.empty?)
        result.na(rollout_not_applicable("a #{pretty_test_name}", batch, owned, skew, idle))
      elsif rolled == 0 && (unconfigured > 0 || !unprepared.empty?)
        result.skipped(rollout_skipped("#{tn}_test_tag", unconfigured, unprepared))
      elsif task_response && restored
        result.passed("CNF for #{pretty_test_name_capitalized} Passed")
      else
        result.failed("CNF for #{pretty_test_name_capitalized} Failed")
      end
    end
  end
end

desc "Test if the CNF can perform a rollback"
scored_task "rollback",
  deps: ["setup:install_cluster_tools"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    container_names = config.common.container_names
    Log.for(t.name).debug { "container_names: #{container_names}" }

    rolled = 0
    unconfigured = 0

    batch = Set(String).new
    owned = Set(String).new
    # Charts from a repository or an OCI registry: the release is moved to
    # the version before and rolled back with `helm rollback` (#2820).
    releases = ReleaseUpgrade.releases(config)
    release_workloads = releases.flat_map(&.workloads).to_set
    unprepared = [] of String
    skew = Set(String).new
    idle = Set(String).new
    restored = true
    task_response = false
    begin
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, _, live|
      # A Job's pod template is immutable and runs once: nothing rolls back.
      if CNFManager.batch_workload?(resource)
        CNFManager.batch_workload_listed?(resource, result, t.name) if batch.add?("#{resource[:kind]}/#{resource[:name]}/#{resource[:namespace]}")
        next true
      end
      next true if operator_owned_listed?(resource, live, owned, result)
      next true if release_workloads.includes?({resource[:kind], resource[:name], resource[:namespace]})
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

      # The version to roll back from: the configured rollback_from_tag, else
      # the image's previous release (#2816). A container with neither is a
      # configuration gap, not a rollback failure: it is left out with the
      # remediation, and the test is skipped when no container had one
      # (#2577).
      config_container = container_names.find{|x| x.name == container_name } if container_names
      configured_tag = config_container.try(&.get_container_tag("rollback_from")) || ""
      rollback_from_tag = rollout_target_tag(result, configured_tag, "rollback_from_tag",
        "#{resource_kind}/#{resource_name} in #{namespace}", container_name, container.as_h["image"].as_s)
      unless rollback_from_tag
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
      skew_line = nil
      unless rollout_status
        why = WorkloadDiagnostics.report(result, resource_kind, resource_name, namespace,
          "#{resource_kind}/#{resource_name} during the rollout to #{image_name}:#{rollback_from_tag}")
        skew_line = version_skew(configured_tag, why)
        unless skew_line
          result.add_impacted_resource(resource_kind, resource_name, namespace, container: container_name,
            reason: "rollout to #{image_name}:#{rollback_from_tag} did not complete within 180s#{rollout_error ? ": #{rollout_error}" : ""}#{why.first?.try { |w| "; #{w}" }}")
        end
      end

      Log.for(t.name).debug { "rollback: rolling back to old version" }
      # An undo that kubectl refuses is the finding this test is for: a
      # workload with revisionHistoryLimit 0 keeps no revision to return to
      # ("no rollout history found"), so a rollback is impossible (#2822).
      undo_ok = begin
        KubectlClient::Rollout.undo(resource_kind, resource_name, namespace: namespace)
        true
      rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
        # kubectl's own error line, past the exception's "kubectl CMD failed,
        # exit code: N, error: " prefix and past the warnings that precede it
        # (an object applied with kubectl warns about its last-applied
        # annotation before the undo is refused).
        lines = ex.message.to_s.sub(/\A.*?error: /m, "").lines.map(&.strip).reject(&.empty?)
        reason = (lines.find { |l| !l.starts_with?("Warning:") } || lines.first.to_s).sub(/\Aerror: /, "")
        result.add_impacted_resource(resource_kind, resource_name, namespace, container: container_name,
          reason: "rollout undo failed: #{reason}")
        if reason.includes?("no rollout history")
          result.append_remediation("#{resource_kind}/#{resource_name} keeps no revision to roll back to: set spec.revisionHistoryLimit to 1 or more (the default is 10), so that kubectl rollout undo has a revision to return to")
        end
        false
      end

      unless undo_ok
        # The undo was refused: put the deployed image back directly, so the
        # tests after this one do not start from the rolled-from image, and
        # fail whatever the rollout did.
        back = KubectlClient::Utils.set_image(resource_kind, resource_name, container_name, image_name, image_tag, namespace: namespace)
        unless back[:status].success?
          result.add_impacted_resource(resource_kind, resource_name, namespace, container: container_name,
            reason: "could not put the deployed image #{image_name}:#{image_tag} back after the refused undo: #{back[:error].to_s.strip}")
        end
        next false
      end
      # Version skew is not judged, now that the undo has put the deployed
      # image back.
      if skew_line
        rolled -= 1
        skew << "#{resource_kind}/#{resource_name} in #{namespace}"
        result.append_description("#{resource_kind}/#{resource_name} in #{namespace}, container #{container_name}: version skew, #{image_name}:#{rollback_from_tag} (the release before the deployed one) does not start under the pod spec the current chart renders (#{skew_line}); not judged, since an upgrade moves image and spec together and there is no previous release of the chart to roll back through")
        next true
      end
      !rollout_status.nil?
    end

    releases.each do |release|
      if release.workloads.empty?
        # Nothing a move would roll out: not judged, as for a Job.
        idle << release.name
        result.append_description("#{release.label}: no Deployment, StatefulSet or DaemonSet of the release to roll out; not judged")
        next
      end
      previous = ReleaseUpgrade.previous_version(release, result)
      unless previous
        unconfigured += 1
        next
      end
      if reason = ReleaseUpgrade.move(release, previous, result, "rollback", false)
        result.append_description("#{release.label}: the release before, #{previous}, could not be installed, so there is no rollback to judge: #{reason}")
        unprepared << release.name
        next
      end
      rolled += 1
      reason = ReleaseUpgrade.rollback(release, result, "rollback")
      task_response &&= reason.nil?
      result.append_description("#{release.label}: moved to #{previous}, then rolled back to #{release.installed} with helm rollback: every workload of the release rolled out") unless reason
    end
    ensure
      restored = ReleaseUpgrade.restore(releases, result, "rollback")
    end

    # A release that is not back at its installed version fails, whatever
    # was judged.
    if !restored
      result.failed("CNF Rollback Failed")
    elsif rolled == 0 && unconfigured == 0 && unprepared.empty? && !(batch.empty? && owned.empty? && skew.empty? && idle.empty?)
      result.na(rollout_not_applicable("a rollback", batch, owned, skew, idle))
    elsif rolled == 0 && (unconfigured > 0 || !unprepared.empty?)
      result.skipped(rollout_skipped("rollback_from_tag", unconfigured, unprepared))
    elsif task_response && restored
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
    # Workloads scaled up and back to their deployed count, for the restart
    # check after the scaling.
    scaled_back = [] of Tuple(String, String, String)
    # A DaemonSet runs one pod per node and has no replica count to scale
    # (#2827): it is judged by the restart half of the test alone, one pod
    # deleted and the DaemonSet back on every node it is scheduled for.
    daemonsets = [] of Tuple(String, String, String)
    # A Deployment the chart runs with strategy Recreate and one replica must
    # never have two pods at once (a single identity, a volume only one pod
    # can mount): scaling it would contradict its own spec, so it is judged
    # by the restart half alone, like a DaemonSet (#2847).
    single_instance = [] of Tuple(String, String, String)

    CNFManager.resource_refs(args, config, ["daemonset"]) do |resource|
      kind, name, namespace = resource[:kind], resource[:name], resource[:namespace]
      # The controller fills in desiredNumberScheduled shortly after the
      # DaemonSet is created; until then, its pods already bound to a node
      # say how many nodes it runs on.
      scheduled = KubectlClient::Get.resource(kind, name, namespace).dig?("status", "desiredNumberScheduled").try(&.as_i?) ||
                  CapacityRestart.pods(kind, name, namespace).count { |pod| pod.dig?("spec", "nodeName").try(&.as_s?).try { |n| !n.empty? } }
      if scheduled == 0
        idle << "#{kind}/#{name} in #{namespace}: scheduled on no node, nothing to restart"
        next
      end
      result.append_description("#{kind}/#{name} in #{namespace}: a DaemonSet runs one pod per node and is not scaled by replica count; judged by a pod restart (#{scheduled} node(s))")
      daemonsets << {kind, name, namespace}
    end

    begin
      CNFManager.resource_refs(args, config, ["deployment", "statefulset"]) do |resource|
        kind = resource[:kind]
        name = resource[:name]
        namespace = resource[:namespace]
        ref = "#{kind}/#{name}"

        replicas = deployed_replicas(kind, name, namespace)
        if replicas == 0
          idle << "#{ref} in #{namespace}: deployed with 0 replicas, not scaled"
          next
        end
        live = KubectlClient::Get.resource(kind, name, namespace)
        if single_instance_by_strategy?(live, replicas)
          result.append_description("#{ref} in #{namespace}: strategy Recreate, never more than one pod at once; not scaled by replica count, judged by a pod restart")
          single_instance << {kind, name, namespace}
          next
        end
        owner = custom_resource_controller(live)
        deployed[{kind, name, namespace}] = replicas
        target = replicas + increase_by
        Log.for(t.name).info { "#{ref} in #{namespace}: deployed with #{replicas} replicas; scaling to #{target}, then back" }

        ready = scale_and_wait(resource, target, args)
        if ready != target.to_s && owner
          operator_owned << "#{ref} in #{namespace}: owned by #{owner}, which sets its replica count; a direct scale to #{target} did not take (#{ready} ready), so it is not counted"
          next
        end
        if ready != target.to_s
          failures << "#{ref} in #{namespace}: increase from #{replicas} to #{target} replicas did not complete (#{ready} ready)"
          why = WorkloadDiagnostics.report(result, kind, name, namespace, "#{ref} while scaling to #{target}")
          result.add_impacted_resource(kind, name, namespace,
            reason: "could not scale up to #{target} replicas (#{ready} ready)#{why.first?.try { |w| ": #{w}" }}")
          next
        end

        ready = scale_and_wait(resource, replicas, args)
        if ready != replicas.to_s
          failures << "#{ref} in #{namespace}: decrease from #{target} back to #{replicas} replicas did not complete (#{ready} ready)"
          why = WorkloadDiagnostics.report(result, kind, name, namespace, "#{ref} while scaling back to #{replicas}")
          result.add_impacted_resource(kind, name, namespace,
            reason: "could not scale back down to #{replicas} replicas (#{ready} ready)#{why.first?.try { |w| ": #{w}" }}")
        else
          scaled_back << {kind, name, namespace}
        end
      end
    ensure
      deployed.each do |(kind, name, namespace), replicas|
        KubectlClient::Utils.scale(kind, name, replicas, namespace)
      end
    end

    idle.each { |line| result.append_description(line) }
    operator_owned.each { |line| result.append_description(line) }

    # Scaling back restores the replica counts, not the application: a
    # clustered StatefulSet (a database replica set, a quorum) can keep the
    # members it lost and stay degraded, and the CNF looks fine until a pod
    # has to start again (#2719). One pod of every scaled workload is
    # restarted, all at once, and each workload must be Ready again, so a CNF
    # the scaling left broken fails here rather than in a later test.
    # DaemonSets and single-instance Deployments are not scaled, so a scaling
    # failure elsewhere does not stop their restart; scaled workloads are
    # restarted only after every scaling went through.
    restart_only = daemonsets + single_instance
    restarted = (failures.empty? ? scaled_back : [] of Tuple(String, String, String)) + restart_only
    unless restarted.empty?
      CapacityRestart.check(restarted, result).each { |failure| failures << failure }
    end
    scaled = deployed.size - operator_owned.size
    restart_summary = [
      daemonsets.empty? ? nil : "#{daemonsets.size} DaemonSet(s) back on every node",
      single_instance.empty? ? nil : "#{single_instance.size} single-instance Deployment(s) Ready again",
    ].compact.join(", ") + " after a pod restart"
    if deployed.empty? && restart_only.empty? && !idle.empty?
      result.na("increase_decrease_capacity not applicable: no Deployment, StatefulSet or DaemonSet runs pods to scale or restart")
    elsif !deployed.empty? && restart_only.empty? && operator_owned.size == deployed.size
      result.na("increase_decrease_capacity not applicable: every workload is sized by an operator's custom resource and none followed a direct scale")
    elsif deployed.empty? && restart_only.empty?
      result.skipped("No Deployment, StatefulSet or DaemonSet to scale or restart")
    elsif failures.empty? && scaled == 0
      result.passed("#{restart_summary}; nothing to scale by replica count")
    elsif failures.empty?
      result.passed("Replicas increased to deployed count + #{increase_by} and decreased back for #{scaled} resource(s)#{restart_only.empty? ? "" : ", #{restart_summary}"}")
    else
      failures.each { |failure| result.append_description(failure) }
      result.append_remediation(increase_decrease_remedy_msg())
      result.failed("Capacity change failed")
    end
  end
end


module CapacityRestart
  alias Ref = Tuple(String, String, String)

  # The workload's pods that are not on their way out.
  def self.pods(kind : String, name : String, namespace : String) : Array(JSON::Any)
    live = KubectlClient::Get.resource(kind, name, namespace)
    KubectlClient::Get.pods_by_resource_labels(live, namespace).reject { |pod| pod.dig?("metadata", "deletionTimestamp") }
  end

  def self.pod_ready?(pod : JSON::Any) : Bool
    WorkloadDiagnostics.pod_ready?(pod)
  end

  # Ready again after the restart: as many pods as the workload asks for,
  # all Ready, and the restarted pod gone. Read from the pods, not the
  # workload's status, which counts the deleted pod for a moment after.
  def self.recovered?(ref : Ref, deleted_uid : String) : Bool
    kind, name, namespace = ref
    pods = self.pods(kind, name, namespace)
    return false if pods.any? { |pod| pod.dig?("metadata", "uid").try(&.as_s?) == deleted_uid }
    # A DaemonSet asks for one Ready pod on every node it is scheduled for.
    # A surge (maxSurge) can leave a second, not yet Ready pod on a node, so
    # it is judged by the nodes that have a Ready pod, counted from the pods
    # and by the DaemonSet's own status, not by every pod being Ready.
    if kind.downcase == "daemonset"
      status = KubectlClient::Get.resource(kind, name, namespace)["status"]?
      desired = status.try(&.["desiredNumberScheduled"]?).try(&.as_i?) || 1
      number_ready = status.try(&.["numberReady"]?).try(&.as_i?) || 0
      ready_nodes = pods.select { |pod| pod_ready?(pod) }.compact_map { |pod| pod.dig?("spec", "nodeName").try(&.as_s?) }.uniq.size
      return number_ready >= desired && ready_nodes >= desired
    end
    desired = deployed_replicas(kind, name, namespace)
    pods.size >= desired && pods.all? { |pod| pod_ready?(pod) }
  rescue KubectlClient::ShellCMD::K8sClientCMDException
    false
  end

  # Every workload restarts at the same time, so start-up dependencies (a
  # database, then a registry, then the rest) resolve one after another:
  # twice the budget one pod gets to become ready.
  TIMEOUT = POD_READINESS_TIMEOUT * 2

  # Deletes one pod of each workload at once and waits for all of them to be
  # Ready again. Returns a failure line per workload that is not, or that had
  # no pod to delete.
  def self.check(refs : Array(Ref), result : CNFManager::TestCaseResult) : Array(String)
    restarted = {} of Ref => String
    # Every workload here runs pods (scaled back to a non-zero count, or a
    # DaemonSet scheduled on a node), so one without a pod is a failure, not
    # a workload to pass over.
    missing = [] of String
    refs.each do |ref|
      kind, name, namespace = ref
      pod = pods(kind, name, namespace).find { |p| p.dig?("metadata", "uid") }
      unless pod
        why = WorkloadDiagnostics.report(result, kind, name, namespace, "#{kind}/#{name} with no pod to restart")
        result.add_impacted_resource(kind, name, namespace,
          reason: "no pod to restart after scaling up and back#{why.first?.try { |w| ": #{w}" }}")
        missing << "#{kind}/#{name} in #{namespace}: no pod to restart, although it should be running one"
        if kind.downcase == "daemonset"
          result.append_remediation("#{kind}/#{name} in #{namespace} is scheduled on a node but runs no pod there. Check why its pods are not created: the DaemonSet's events (kubectl describe daemonset #{name} -n #{namespace}) name the cause, such as an admission policy or webhook that refuses its pod, a namespace resource quota that is used up, or a NoExecute taint added to the node that its tolerations do not cover.")
        end
        next
      end
      KubectlClient::Delete.resource("pod", pod.dig("metadata", "name").as_s, namespace, extra_opts: "--wait=false")
      restarted[ref] = pod.dig("metadata", "uid").as_s
    end
    started = Time.utc
    pending = restarted.keys
    until pending.empty? || (Time.utc - started).total_seconds > TIMEOUT
      sleep 2.seconds
      pending.reject! { |ref| recovered?(ref, restarted[ref]) }
    end

    took = (Time.utc - started).total_seconds.round.to_i
    result.append_description("Restart after scaling: one pod of each of #{restarted.size} workload(s) deleted at once; #{restarted.size - pending.size} Ready again within #{took} s")
    not_ready = pending.map do |ref|
      kind, name, namespace = ref
      why = WorkloadDiagnostics.report(result, kind, name, namespace, "#{kind}/#{name} after a pod restart following the scaling")
      result.add_impacted_resource(kind, name, namespace,
        reason: "not Ready within #{TIMEOUT}s of a pod restart after scaling up and back#{why.first?.try { |w| ": #{w}" }}")
      "#{kind}/#{name} in #{namespace}: not Ready again within #{TIMEOUT}s of a pod restart after scaling up and back; the scaling may have left the application degraded"
    end
    missing + not_ready
  end
end

def increase_decrease_remedy_msg()
<<-TEMPLATE

Replica failure can be due to insufficent permissions, image pull errors and other issues.
Learn more on remediation in the test documentation: https://github.com/lfn-cnti/testsuite/blob/main/docs/TEST_DOCUMENTATION.md#increase-decrease-capacity
TEMPLATE
end

# The replica count a resource was deployed with: its live spec, defaulting
# to Kubernetes' own default of 1 when the field is unset.
# The workload's controller owner, as "Kind/name", when it is a custom
# resource (an API group other than the core, apps and batch ones): an
# operator's object, not a Kubernetes controller. Nil otherwise.
# Registry tags listed during this run, by repository; nil when the registry
# could not be read.
ROLLOUT_REGISTRY_TAGS = {} of String => Array(String)?

# A workload whose controller owner is an operator's custom resource takes
# its image from that resource: a direct change is reverted, or fought, and
# the result would say more about the operator's reconcile timing than about
# the CNF (#2810). Such a workload is named once in the details and left
# alone, whatever tag is configured; it counts as neither rolled nor
# unconfigured. True when the workload is one of those.
def operator_owned_listed?(resource, live : JSON::Any, owned : Set(String), result) : Bool
  owner = custom_resource_controller(live)
  return false unless owner
  ref = "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}"
  if owned.add?(ref)
    result.append_description("#{ref}: image set by #{owner}, not rolled; upgrade it through the custom resource")
  end
  true
end

# Why a rollout test does not apply: every workload either runs to
# completion, is owned by an operator, or cannot be judged one image at a
# time because its previous image does not run under the current spec.
def rollout_not_applicable(action : String, batch : Set(String), owned : Set(String), skew : Set(String) = Set(String).new, idle : Set(String) = Set(String).new) : String
  parts = [] of String
  parts << "runs to completion (a Job or CronJob)" unless batch.empty?
  parts << "takes its image from an operator's custom resource" unless owned.empty?
  parts << "has a previous image that does not start under the current pod spec (version skew, see the details)" unless skew.empty?
  parts << "comes from a chart with no Deployment, StatefulSet or DaemonSet to roll out" unless idle.empty?
  "Every workload of the CNF #{parts.join(" or ")}, #{action} does not apply"
end

# Why a rollout test was skipped: nothing to roll was configured, or found
# in a registry, or a chart's previous release could not be installed.
def rollout_skipped(tag_key : String, unconfigured : Int32, unprepared : Array(String)) : String
  parts = [] of String
  parts << "No usable #{tag_key} configured for any container, and no previous release to take from the registry: see the remediation" if unconfigured > 0
  parts << "The release before could not be installed for chart#{unprepared.size == 1 ? "" : "s"} #{unprepared.join(", ")}, so there is nothing to judge: see the details" unless unprepared.empty?
  parts.join(". ")
end

# A previous image, taken from the registry rather than configured, that
# crash-loops under the pod spec the current chart renders: the line that
# says so, else nil. The old binary meets arguments, environment or mounts
# it never shipped with; an upgrade never produces that combination. A tag
# the user configured is their assertion that the image fits, and its crash
# stays a failure.
def version_skew(configured_tag : String, why : Array(String)) : String?
  return nil unless configured_tag.empty?
  why.find { |line| line.includes?("CrashLoopBackOff") }
end

# The tag a rollout test moves a container to, or nil when there is none, with
# the reason recorded on the result. The tag configured in cnti-testsuite.yaml
# comes first; a configured tag equal to the deployed one rolls out nothing
# and is a configuration gap. Without one, the image's previous release in
# its registry (#2816): the closest older tag of the same form.
def rollout_target_tag(result, configured : String, tag_key : String, label : String, container_name : String, image : String) : String?
  deployed = ImageTag.digest?(image) ? nil : ImageTag.tag_of(image)
  unless configured.empty?
    if configured == ImageTag.tag_of(image)
      result.append_remediation("#{tag_key} #{configured} for container #{container_name} is the deployed tag, so nothing would roll out: set it to another released version")
      return nil
    end
    return configured
  end
  repository = ImageTag.repository_of(image)
  tags = if deployed && ImageTag.version_form(deployed)
           ROLLOUT_REGISTRY_TAGS.fetch(repository) { ROLLOUT_REGISTRY_TAGS[repository] = ClusterTools.image_tags(repository) }
         end
  previous = deployed && tags ? ImageTag.previous_release(deployed, tags) : nil
  if previous
    result.append_description("#{label}, container #{container_name}: no #{tag_key} configured, using #{previous}, the release before the deployed #{deployed}")
    return previous
  end
  why = if ImageTag.digest?(image)
          "its image is pinned by digest"
        elsif deployed.nil?
          "its image has no tag"
        elsif ImageTag.version_form(deployed).nil?
          "its tag #{deployed} names no version"
        elsif tags.nil?
          "the tags of #{repository} could not be listed"
        else
          "#{repository} has no older release of the form of #{deployed}"
        end
  result.append_remediation("No #{tag_key} configured for container #{container_name}, and #{why}: add container_names with a #{tag_key} to cnti-testsuite.yaml")
  nil
end

def custom_resource_controller(workload : JSON::Any) : String?
  controller = workload.dig?("metadata", "ownerReferences").try(&.as_a?).try &.find { |ref| ref["controller"]?.try(&.as_bool?) }
  return nil unless controller
  api_version = controller["apiVersion"]?.try(&.as_s?) || ""
  group = api_version.includes?('/') ? api_version.split('/').first : ""
  return nil if ["", "apps", "batch"].includes?(group)
  "#{controller["kind"]?.try(&.as_s?)}/#{controller["name"]?.try(&.as_s?)}"
end

# A Deployment run with strategy Recreate and one replica: never more than one
# pod at once, so it is not scaled by replica count (#2847).
def single_instance_by_strategy?(resource : JSON::Any, replicas : Int32) : Bool
  resource["kind"]?.try(&.as_s?) == "Deployment" && replicas == 1 &&
    resource.dig?("spec", "strategy", "type").try(&.as_s?) == "Recreate"
end

def deployed_replicas(kind : String, name : String, namespace : String) : Int32
  KubectlClient::Get.resource(kind, name, namespace).dig?("spec", "replicas").try(&.as_i) || 1
end

# Scales the workload and returns the ready replica count once it settles.
def scale_and_wait(resource : NamedTuple(kind: String, name: String, namespace: String), target : Int32, args) : String
  Log.for("scale_and_wait").info { "#{resource[:kind]}/#{resource[:name]} in #{resource[:namespace]}: scaling to #{target}" }
  KubectlClient::Utils.scale(resource[:kind], resource[:name], target, resource[:namespace])
  wait_for_scaling(resource, target.to_s, args)
end

def wait_for_scaling(resource : NamedTuple(kind: String, name: String, namespace: String), target_replica_count, args)
  Log.debug { "target_replica_count: #{target_replica_count}" }
  replicas_cmd = "kubectl get #{resource[:kind]} #{resource[:name]} -o=jsonpath='{.status.readyReplicas}' -n #{resource[:namespace]}"
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
    Log.debug { "current_replicas before get #{resource[:kind]}: #{current_replicas}" }
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
       resource.dig?("spec", "template", "metadata", "annotations"),
       resource.dig?("spec", "jobTemplate", "spec", "template", "metadata", "annotations")].each do |annotations|
        annotations.try(&.as_h?).try(&.each do |key, value|
          if key == CNI_NETWORKS_ANNOTATION
            flag.call("requests additional CNI networks: #{CNI_NETWORKS_ANNOTATION}=#{value}")
          elsif (vendor = CNI_VENDOR_MARKERS.find { |m| key.includes?(m) })
            flag.call("carries the CNI-specific annotation #{key}")
          end
        end)
      end

      # SR-IOV device resources requested by any container.
      [resource.dig?("spec", "containers"),
       resource.dig?("spec", "template", "spec", "containers"),
       resource.dig?("spec", "jobTemplate", "spec", "template", "spec", "containers")].each do |containers|
        containers.try(&.as_a?).try(&.each do |container|
          container_name = container.dig?("name").try(&.as_s?)
          ["requests", "limits"].each do |section|
            container.dig?("resources", section).try(&.as_h?).try(&.each_key do |key|
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
    # dry-run of the CNF's manifest returns the same Warning headers kubectl
    # shows on install, for every resource whatever its install method,
    # without depending on a log file (#2578).
    #
    # Some warnings are only issued on create (the Ingress strategy warns
    # about kubernetes.io/ingress.class when the annotation is new, not when
    # an installed object is re-applied unchanged), so the manifest is
    # dry-run both as a create and as an apply and the warnings are joined.
    # A resource whose *name* contains "deprecated" is not a finding: the
    # word has to stand on its own in the warning.
    #
    # What the CNF ships and what was read back from the cluster are dry-run
    # apart (#2809). A failure on the shipped part is the CNF's and is a skip
    # with the reason. The read-back copies (an operator's workloads, the
    # label-identified objects, discovered CRDs) are dry-run, as a create and
    # as an apply, without the fields the server assigned them, for the
    # warnings only: a copy that fails to dry-run says nothing about the CNF
    # (the create of an object that exists is refused, after its warnings),
    # and an operator's own API versions are not visible in a copy the server
    # returns in its preferred version, so only a deprecated field or
    # annotation can be found there. Re-applying a copy unchanged is a no-op
    # update, on which the API server does not repeat the warnings it gives
    # on create, so the create dry-run is the one that finds them.
    deprecated = /(?<![\w-])deprecated(?![\w-])/i
    collect = ->(stderr : String) do
      stderr.lines.map(&.strip).select { |line| line.starts_with?("Warning:") && line =~ deprecated }.map { |line| line.sub(/^Warning:\s*/, "") }
    end
    parts = CNFInstall::Manifest.split_by_source(File.read(COMMON_MANIFEST_FILE_PATH))
    shipped_path = "#{File.dirname(COMMON_MANIFEST_FILE_PATH)}/deprecated-shipped.yml"
    read_back_path = "#{File.dirname(COMMON_MANIFEST_FILE_PATH)}/deprecated-read-back.yml"
    File.write(shipped_path, parts[:shipped])
    # Server-side apply: a client-side apply stores the whole object in the
    # last-applied-configuration annotation, which the API server refuses
    # beyond 256 KiB (KEDA's CRDs), and warns on every Helm-installed object
    # that lacks the annotation; the deprecation warnings are the API's and
    # come back either way. The conflicts a dry-run would report against
    # Helm's field manager change nothing, so they are forced.
    resp = KubectlClient::ShellCMD.run("kubectl apply --server-side --force-conflicts --dry-run=server -f #{shipped_path}", logger)
    create = KubectlClient::ShellCMD.run("kubectl create --dry-run=server -f #{shipped_path}", logger)
    warnings = collect.call(resp[:error]) + collect.call(create[:error])
    unless parts[:read_back].strip.empty?
      cleaned = CNFInstall::Manifest.strip_live_fields(CNFInstall::Manifest.manifest_string_to_ymls(parts[:read_back]))
      File.write(read_back_path, CNFInstall::Manifest.combine_ymls_as_manifest_string(cleaned))
      live = KubectlClient::ShellCMD.run("kubectl apply --server-side --force-conflicts --dry-run=server -f #{read_back_path}", logger)
      live_create = KubectlClient::ShellCMD.run("kubectl create --dry-run=server -f #{read_back_path}", logger)
      {"apply" => live, "create" => live_create}.each do |verb, run|
        next if run[:status].success?
        logger.info { "Dry-run #{verb} of the objects read back from the cluster did not succeed (not held against the CNF): #{run[:error].lines.reject(&.starts_with?("Warning:")).first?.to_s.strip}" }
      end
      warnings += collect.call(live[:error]) + collect.call(live_create[:error])
    end
    File.delete?(shipped_path)
    File.delete?(read_back_path)
    warnings = warnings.uniq
    logger.info { "Found #{warnings.size} deprecation warning(s)" }

    if warnings.empty? && !resp[:status].success?
      # The first line that is an error, not a Warning.
      reason = resp[:error].lines.map(&.strip).reject { |line| line.empty? || line.starts_with?("Warning:") }.first? || resp[:error].lines.first?.to_s.strip
      logger.info { "Dry-run of the CNF's manifest failed:\n#{resp[:error]}" }
      result.skipped("Could not dry-run the CNF manifest against the API server: #{reason}")
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

desc "Check that the CNF's Services declare dual-stack"
scored_task "dual_stack",
  type: CNFManager::TestType::Bonus,
  emoji: "🌐" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Checks the declaration only: that each Service opts in to dual-stack by
    # setting spec.ipFamilyPolicy to PreferDualStack or RequireDualStack. It does
    # NOT check that the CNF works over IPv6; that needs a dual-stack cluster and
    # is not tested here.
    #
    # PreferDualStack works on IPv4-only, IPv6-only and dual-stack clusters
    # alike — it falls back to single-stack where dual-stack is not enabled. A
    # Service without ipFamilyPolicy works on any single-family cluster (it gets
    # a cluster IP from the configured range), but on a dual-stack cluster it
    # gets only the cluster's primary family. Declaring PreferDualStack closes
    # that gap without affecting single-stack clusters.
    dual_stack_policies = ["PreferDualStack", "RequireDualStack"]
    violation_list = [] of NamedTuple(kind: String, name: String, namespace: String, reason: String)
    applicable = 0
    missing = [] of String

    CNFManager.resource_refs(args, config, ["service"]) do |svc|
      begin
        live = KubectlClient::Get.resource(svc[:kind], svc[:name], svc[:namespace])
      rescue KubectlClient::ShellCMD::NotFoundError
        # A Service in the manifest but gone from the cluster cannot be judged.
        missing << "Service/#{svc[:name]} in #{svc[:namespace]}"
        next nil
      end
      # ExternalName Services map to a DNS name and have no IP families to judge.
      unless live.dig?("spec", "type").try(&.as_s?) == "ExternalName"
        applicable += 1
        policy = live.dig?("spec", "ipFamilyPolicy").try(&.as_s?)
        if policy && dual_stack_policies.includes?(policy)
          result.append_description("Service/#{svc[:name]} in #{svc[:namespace]}: #{policy}")
        else
          actual = policy || "unset"
          violation_list << {kind: svc[:kind], name: svc[:name], namespace: svc[:namespace],
                             reason: "spec.ipFamilyPolicy is #{actual}: on a dual-stack cluster this Service receives only the cluster's primary address family"}
        end
      end
      nil
    end

    missing.each { |m| result.append_description("#{m}: not found in the cluster, not judged") }

    if applicable == 0 && !missing.empty?
      result.append_remediation("Make sure the CNF's Services exist in the cluster (reinstall the CNF if they were removed), then run the test again.")
      result.skipped("None of the CNF's Services were found in the cluster; dual-stack declaration could not be checked")
    elsif applicable == 0
      result.na("The CNF declares no applicable Services; dual-stack declaration does not apply")
    elsif violation_list.empty?
      # Name only what was judged: some Services may not have been in the cluster.
      checked = "All #{applicable} Service(s) found in the cluster declare dual-stack (PreferDualStack or RequireDualStack)"
      checked += "; #{missing.size} declared Service(s) were not found and not checked" unless missing.empty?
      result.passed(checked)
    else
      violation_list.each do |v|
        result.add_impacted_resource(v[:kind], v[:name], v[:namespace], reason: v[:reason])
      end
      result.append_remediation("Set spec.ipFamilyPolicy to PreferDualStack on the CNF's Services so they are reachable over both address families on a dual-stack cluster. PreferDualStack works on single-stack clusters too — it falls back to one family without affecting behaviour.")
      result.failed("Found #{violation_list.size} Service(s) that do not declare dual-stack")
    end
  end
end
