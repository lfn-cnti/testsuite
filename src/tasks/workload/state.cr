# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../../modules/kubectl_client"
require "../utils/volume_elasticity.cr"
require "../../modules/k8s_netstat"

desc "The CNF test suite checks if state is stored in a custom resource definition or a separate database (e.g. etcd) rather than requiring local storage.  It also checks to see if state is resilient to node failure"
category_task "state", ["no_local_volume_configuration", "elastic_volumes", "database_persistence", "node_drain"]

# Kinds a drain can evict and that come back on their own. A bare Pod is
# deleted for good (drain refuses it without --force) and DaemonSet pods are
# left in place by drain, so neither can be tested this way.
NODE_DRAIN_KINDS = ["deployment", "statefulset", "replicaset"]

desc "Does the CNF survive the loss of a node? Each node hosting its pods is drained once"
scored_task "node_drain",
  type: CNFManager::TestType::Essential,
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    schedulable = KubectlClient::Get.schedulable_nodes_list.compact_map { |n| n.dig?("metadata", "name").try(&.as_s?) }
    if schedulable.size <= 1
      result.skipped("node_drain requires at least two schedulable nodes, found #{schedulable.size}")
      next
    end

    # The CNF's workloads and the pods each one has scheduled (#2620): the
    # drains are per node, and every workload with a pod on a node is
    # judged when that node goes.
    workloads = [] of NamedTuple(kind: String, name: String, namespace: String)
    pods_of = {} of NamedTuple(kind: String, name: String, namespace: String) => Array(JSON::Any)
    CNFManager.resource_refs(args, config, WORKLOAD_RESOURCE_KIND_NAMES) do |ref|
      label = "#{ref[:kind]}/#{ref[:name]} in #{ref[:namespace]}"
      unless NODE_DRAIN_KINDS.includes?(ref[:kind].downcase)
        result.append_description("#{label}: a #{ref[:kind]} cannot be drained and rescheduled (a bare Pod is deleted for good, DaemonSet pods stay), node_drain is not applicable to it")
        next
      end
      live = KubectlClient::Get.resource(ref[:kind], ref[:name], ref[:namespace])
      pods = KubectlClient::Get.pods_by_resource_labels(live, ref[:namespace]).reject { |pod| pod.dig?("metadata", "deletionTimestamp") }
      workloads << ref
      pods_of[ref] = pods
    end
    if workloads.empty?
      result.na("node_drain not applicable: no Deployment, StatefulSet or ReplicaSet to reschedule")
      next
    end

    by_node = {} of String => Array(NamedTuple(kind: String, name: String, namespace: String))
    pods_of.each do |ref, pods|
      pods.each do |pod|
        node = pod.dig?("spec", "nodeName").try(&.as_s?)
        next if node.nil?
        (by_node[node] ||= [] of NamedTuple(kind: String, name: String, namespace: String)) << ref unless by_node[node]?.try(&.includes?(ref))
      end
    end
    failed = 0
    workloads.each do |ref|
      next if by_node.values.any?(&.includes?(ref))
      result.add_impacted_resource(ref[:kind], ref[:name], ref[:namespace], reason: "no scheduled pod to drain")
      failed += 1
    end

    by_node.each do |node, refs|
      unless schedulable.includes?(node)
        result.append_description("Node #{node} hosts #{refs.size} workload(s) of the CNF but is not schedulable; it was not drained")
        next
      end
      pod_count = refs.sum { |ref| pods_of[ref].count { |pod| pod.dig?("spec", "nodeName").try(&.as_s?) == node } }
      StatusLine.push "Draining #{node} (#{pod_count} pod(s) of #{refs.size} workload(s))..."
      started = Time.utc
      cordoned = false
      begin
        KubectlClient::Utils.cordon(node)
        cordoned = true
        drain = KubectlClient::Utils.drain(node, GENERIC_OPERATION_TIMEOUT)
        evicted_in = (Time.utc - started).total_seconds.round.to_i
        unless drain[:status].success?
          # An eviction the API refuses (a PodDisruptionBudget, most often)
          # or a drain that ran out of time: the node's workloads did not go
          # and cannot be judged, and the reason is kubectl's own.
          reason = drain[:error].lines.map(&.strip).find { |l| l =~ /error|cannot|Cannot|timed out/i } || drain[:error].lines.first?.to_s.strip
          result.append_description("Node #{node}: drain did not complete within #{GENERIC_OPERATION_TIMEOUT}s: #{reason}")
          refs.each do |ref|
            result.add_impacted_resource(ref[:kind], ref[:name], ref[:namespace], reason: "eviction from node #{node} did not complete: #{reason}")
          end
          failed += refs.size
          next
        end
        result.append_description("Node #{node}: #{pod_count} pod(s) of #{refs.size} workload(s) evicted in #{evicted_in} s")

        # Recovery is judged while the node is still cordoned: a workload
        # that is Ready again now has come back on another node.
        refs.each do |ref|
          label = "#{ref[:kind]}/#{ref[:name]} in #{ref[:namespace]}"
          since = Time.utc
          if KubectlClient::Wait.resource_wait_for_install(kind: ref[:kind], resource_name: ref[:name], wait_count: POD_READINESS_TIMEOUT, namespace: ref[:namespace])
            result.append_description("#{label}: Ready again on another node #{(Time.utc - since).total_seconds.round.to_i} s after eviction")
          else
            why = WorkloadDiagnostics.report(result, ref[:kind], ref[:name], ref[:namespace], "#{label} after draining #{node}")
            result.add_impacted_resource(ref[:kind], ref[:name], ref[:namespace],
              reason: "not Ready within #{POD_READINESS_TIMEOUT}s of eviction from node #{node}#{why.first?.try { |w| ": #{w}" }}")
            failed += 1
          end
        end

        # Keep the node out for the rest of the hold, so a recovery that
        # only lasts until the node returns does not count.
        remaining = NODE_DRAIN_TOTAL_CHAOS_DURATION - (Time.utc - started).total_seconds.to_i
        sleep(remaining.seconds) if remaining > 0
      ensure
        # The node comes back whatever happened above; a raise here would
        # leave every later test one node short.
        if cordoned
          begin
            KubectlClient::Utils.uncordon(node)
          rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
            Log.for(t.name).error { "uncordon #{node}: #{ex.message}" }
            result.append_description("Node #{node} could not be uncordoned: #{ex.message.to_s.lines.first?.to_s.strip}")
          end
        end
        StatusLine.pop
      end
    end

    drained = by_node.keys.select { |node| schedulable.includes?(node) }.size
    if failed == 0
      result.passed("node_drain passed: #{drained} node(s) drained, #{workloads.size} workload(s) rescheduled")
    else
      result.append_remediation("Make every workload survive the loss of the node it runs on: more than one replica spread across nodes, no node-local state, readiness that reflects the service, and PodDisruptionBudgets that leave room for an eviction.")
      result.failed("node_drain failed: #{failed} workload(s) did not come back after a drain")
    end
  end
end

desc "Does the CNF use an elastic persistent volume"
scored_task "elastic_volumes",
  type: CNFManager::TestType::Bonus,
  emoji: "🧫" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # The volume each claim is bound to is judged, not the name of its
    # provisioner (#2665): a volume tied to one node is not elastic. One
    # that the cluster's default storage class provisioned is the cluster's
    # choice and is listed, not held against the CNF.
    claims = 0
    elastic = 0
    node_bound = 0
    cluster_choice = 0
    unbound = 0
    all_volumes = KubectlClient::Get.resource("pv")["items"].as_a

    CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, _|
      namespace = resource["namespace"]
      label = "#{resource["kind"]}/#{resource["name"]} in #{namespace}"
      full_resource = KubectlClient::Get.resource(resource["kind"], resource["name"], namespace)

      VolumeElasticity.claim_names(full_resource).each do |claim|
        claims += 1
        pv = all_volumes.find do |volume|
          volume.dig?("spec", "claimRef", "name").try(&.as_s?) == claim &&
            volume.dig?("spec", "claimRef", "namespace").try(&.as_s?) == namespace
        end
        unless pv
          result.append_description("#{label}: claim #{claim} is not bound to a PersistentVolume, elasticity undetermined")
          unbound += 1
          next
        end

        class_name = pv.dig?("spec", "storageClassName").try(&.as_s?)
        storage_class = begin
          KubectlClient::Get.resource("storageclasses", class_name) if class_name && !class_name.empty?
        rescue KubectlClient::ShellCMD::NotFoundError
          nil
        end
        judgement = VolumeElasticity.judge(pv, storage_class)
        line = "claim #{claim}, PersistentVolume #{pv.dig?("metadata", "name")}: #{judgement[:reason]}"
        case judgement[:verdict]
        in .elastic?
          elastic += 1
          result.append_description("#{label}: #{line}")
        in .cluster_choice?
          cluster_choice += 1
          result.append_description("#{label}: #{line}; not judged")
        in .node_bound?
          node_bound += 1
          result.add_impacted_resource(resource["kind"], resource["name"], namespace, reason: line)
        end
      end
      true
    end

    Log.for(t.name).info { "claims: #{claims}, elastic: #{elastic}, node-bound: #{node_bound}, cluster's choice: #{cluster_choice}, unbound: #{unbound}" }
    if claims == 0
      result.na("No persistent volumes are used")
    elsif node_bound > 0
      result.append_remediation("Claim the storage from a storage class whose volumes can follow the workload to another node, and do not bind the claim to a local or hostPath PersistentVolume.")
      result.failed("Some of the used volumes are not elastic")
    elsif elastic > 0
      result.passed("All used volumes are elastic")
    elsif cluster_choice > 0
      result.na("The cluster's default storage class provisions volumes tied to a node, elasticity is not the CNF's choice here")
    else
      result.skipped("#{unbound} persistent volume claim(s) not bound to a PersistentVolume: elasticity could not be determined")
    end
  end
end

desc "Does the CNF use a database which uses perisistence in a cloud native way"
scored_task "database_persistence",
  emoji: "🧫",
  fail: -1 do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Databases among the CNF's workloads, recognised as shared_database
    # does: MariaDB/MySQL, PostgreSQL, MongoDB, Redis, Cassandra and etcd, by
    # image name or port (#2658).
    #
    # What is judged is what the CNF decides: whether the database claims
    # persistent storage, through a PersistentVolumeClaim or a
    # volumeClaimTemplate, whatever the kind of its workload. Which
    # provisioner backs the claim is the cluster's choice, and its
    # elasticity is the subject of elastic_volumes.
    found = 0
    judged = 0
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, volumes|
      database = containers.as_a.compact_map { |container| Netstat::Database.detect(container) }.first?
      next true unless database
      found += 1
      namespace = resource["namespace"]
      label = "#{resource["kind"]}/#{resource["name"]} in #{namespace}"

      full_resource = KubectlClient::Get.resource(resource["kind"], resource["name"], namespace)
      claims = VolumeElasticity.claim_names(full_resource)

      unless claims.empty?
        judged += 1
        result.append_description("#{label} runs #{database[:name]} on persistent storage: #{claims.join(", ")}")
        next true
      end

      # Redis (Valkey is recognised under the same name) is often a cache
      # that keeps nothing on purpose, and a cache
      # cannot be told from a data store from the outside.
      if database[:name] == "Redis"
        result.append_description("#{label} runs Redis without a persistent volume; it may be a cache, its persistence was not judged")
        next true
      end

      judged += 1
      result.add_impacted_resource(resource["kind"], resource["name"], namespace, reason: "runs #{database[:name]} without a persistent volume")
      false
    end

    known = Netstat::Database::KNOWN.map(&.[:name]).join(", ")
    if found == 0
      result.na("No database workload found in the CNF (looked for #{known})")
    elsif judged == 0
      result.na("The CNF's only database is a Redis without a persistent volume, persistence was not judged")
    elsif task_response
      result.passed("CNF uses database with cloud-native persistence")
    else
      result.append_remediation("Give the database a persistent volume: a volumeClaimTemplate in a StatefulSet, or a PersistentVolumeClaim.")
      result.failed("CNF uses database without cloud-native persistence (ভ_ভ) ރ 💾")
    end
  end

  # TODO When using a default StorageClass, the storageclass name will be populated in the persistent volumes claim post-creation.
  # TODO Inspect the workload resource and search for any "Persistent Volume Claims" --> https://loft.sh/blog/kubernetes-persistent-volumes-examples-and-best-practices/#what-are-persistent-volume-claims-pvcs 
  # TODO Inspect the Persistent Volumes Claim and determine if a Storage Class is use. If a Storage Class is defined, dynamic provisioning is in use. If no storge class is defined, static provisioningis in use -> https://v1-20.docs.kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim

  # TODO If using dynamic provisioning, find the and inspect the associated storageClass and find the provisioning driver being used -> https://kubernetes.io/docs/concepts/storage/storage-classes/#the-storageclass-resource
  # TODO Match and check if the provisioning driver used is of an elastic volume type.
  # TODO If using static provisioning, find the and inspect the associated Persistent Volume and determine the provisioning driver being used -> 
  # TODO Match and check if the provisioning driver used is of an elastic volume type.
end

desc "Does the CNF use a non-cloud native data store: local volumes on the node?"
scored_task "no_local_volume_configuration",
  type: CNFManager::TestType::Bonus,
  emoji: "💾" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Note: A storageClassName value of "local-storage" is insufficient to determine if the
    # persistent volume is indeed local storage.  This is because the storageClass can be redefined
    # to be anything (e.g. the name local-storage can be redefined to be block storage behind the scenes)
    # The PersistentVolume a claim is bound to is the authority: spec.local.path.
    #
    # No rescue-all here: the previous one turned any error reading a resource or
    # a volume into a pass (#2594). A kubectl failure now errors the test, and a
    # claim that is not bound to any PV is reported as undetermined, not as clean.
    local = 0
    unbound = 0
    CNFManager.cnf_workload_resources(args, config) do |resource|
      kind = resource["kind"].as_s
      name = resource.dig("metadata", "name").as_s
      namespace = resource.dig?("metadata", "namespace").try(&.as_s?)
      pod_spec = resource.dig?("spec", "template", "spec") || resource.dig?("spec")
      volumes = pod_spec.try(&.dig?("volumes")).try(&.as_a?) || [] of YAML::Any
      volumes.each do |volume|
        claim_name = volume.dig?("persistentVolumeClaim", "claimName").try(&.as_s?)
        next unless claim_name
        volume_name = volume.dig?("name").try(&.as_s?) || claim_name
        bound = KubectlClient::Get.pv_items_by_claim_name(claim_name)
        if bound.empty?
          result.append_description("#{kind}/#{name} volume #{volume_name}: claim #{claim_name} is not bound to a PersistentVolume, storage type undetermined")
          unbound += 1
          next
        end
        bound.each do |pv|
          path = pv.dig?("spec", "local", "path").try(&.as_s?)
          next unless path
          result.add_impacted_resource(kind, name, namespace, reason: "volume #{volume_name} (claim #{claim_name}) is bound to PersistentVolume #{pv.dig?("metadata", "name")} with local path #{path}")
          local += 1
        end
      end
      true
    end

    if local > 0
      result.append_remediation("Back the claim with a network or cloud volume through a StorageClass; a local PersistentVolume ties the workload to one node and its disk.")
      result.failed("local storage configuration volumes found (ভ_ভ) ރ")
    elsif unbound > 0
      result.skipped("#{unbound} persistent volume claim(s) not bound to a PersistentVolume: storage type could not be determined")
    else
      result.passed("local storage configuration volumes not found 🖥️")
    end
  end
end
