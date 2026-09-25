# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../../modules/kubectl_client"

desc "The CNF test suite checks if state is stored in a custom resource definition or a separate database (e.g. etcd) rather than requiring local storage.  It also checks to see if state is resilient to node failure"
category_task "state", ["no_local_volume_configuration", "elastic_volumes", "database_persistence", "node_drain"]

ELASTIC_PROVISIONING_DRIVERS_REGEX = /kubernetes.io\/aws-ebs|kubernetes.io\/azure-file|kubernetes.io\/azure-disk|kubernetes.io\/cinder|kubernetes.io\/gce-pd|kubernetes.io\/glusterfs|kubernetes.io\/quobyte|kubernetes.io\/rbd|kubernetes.io\/vsphere-volume|kubernetes.io\/portworx-volume|kubernetes.io\/scaleio|kubernetes.io\/storageos|rook-ceph.rbd.csi.ceph.com/


ELASTIC_PROVISIONING_DRIVERS_REGEX_SPEC = /kubernetes.io\/aws-ebs|kubernetes.io\/azure-file|kubernetes.io\/azure-disk|kubernetes.io\/cinder|kubernetes.io\/gce-pd|kubernetes.io\/glusterfs|kubernetes.io\/quobyte|kubernetes.io\/rbd|kubernetes.io\/vsphere-volume|kubernetes.io\/portworx-volume|kubernetes.io\/scaleio|kubernetes.io\/storageos|rook-ceph.rbd.csi.ceph.com|rancher.io\/local-path/

module Volume
  def self.pvc_volumes(volumes : Array(JSON::Any)) : Array(JSON::Any)
    volumes.select { |v| v.dig?("persistentVolumeClaim", "claimName") }
  end

  def self.elastic_by_volumes?(volumes : Array(JSON::Any), namespace : String? = nil) : {elastic: Bool, missing_classes: Array(String)}
    Log.info {"Volume.elastic_by_volumes"}
    storage_class_names = storage_class_by_volumes(volumes, namespace)
    result = StorageClass.elastic_by_storage_class?(storage_class_names, namespace)
    Log.info {"Volume.elastic_by_volumes elastic: #{result[:elastic]}"}
    result
  end
  # def self.elastic?(volumes, namespace : String? = nil)
  #   Log.info {"elastic? overload"}
  #   elastic?(volumes, namespace) {}
  # end
  # def self.elastic?(volumes, namespace : String? = nil, &block : -> JSON::Any | Nil)
  #   Log.info {"storge_class_by_volumes? "}
  #   Log.info {"storge_class_by_volumes? volumes: #{volumes}"}
  #   elastic = false
  #   #### default
  #   volume_claims = volumes.as_a.select{ |x| x.dig?("persistentVolumeClaim", "claimName") } 
  #   Log.info {"volume_claims #{volume_claims}"}
  #   dynamic_claims = volume_claims.reduce( [] of Hash(String, JSON::Any)) do |acc, claim| 
  #     resource = KubectlClient::Get.resource("pvc", claim.dig?("persistentVolumeClaim", "claimName"), namespace)
  #     Log.info {"pvc resource #{resource}"}
  #     # todo determine whether if resource uses a volume claim or a volume claim template
  #     # todo if no pvc
  #     # todo check for volumeClaimTemplate
  #     # todo  get metadata name field
  #     # todo  combine name <metatdataname>-<workloadresourcename>-0
  #     if block
  #       resource = yield unless resource
  #       Log.info {"block resource #{resource}"}
  #     else
  #       Log.info {"block is nil"}
  #     end
  #
  #     if resource && resource.dig?("spec", "storageClassName")
  #       Log.info {"StorageClass: #{resource.dig?("spec", "storageClassName")}"}
  #       acc << { "claim_name" =>  claim.dig("persistentVolumeClaim", "claimName"), "class_name" => resource.dig("spec", "storageClassName") }
  #     else
  #       acc
  #     end
  #   end
  #   Log.info {"Dynamic Claims: #{dynamic_claims}"}
  #   #todo elastic_by_storage_class?
  #   provisoners = dynamic_claims.reduce( [] of String) do |acc, claim| 
  #     resource = KubectlClient::Get.resource("storageclasses", claim.dig?("class_name"), namespace)
  #     if resource.dig?("provisioner")
  #       acc << resource.dig("provisioner").as_s 
  #     else
  #       acc
  #     end
  #   end
  #   Log.info {"Provisoners: #{provisoners}"}
  #   provisoners.each do |provisoner|
  #     if ENV["CNTI_TESTSUITE_ENV"]? == "TEST"
  #       if (provisoner =~ ELASTIC_PROVISIONING_DRIVERS_REGEX_SPEC) 
  #         Log.info {"provisioner test mode"}
  #         Log.info {"Provisoners: #{provisoners}"}
  #         elastic = true
  #       end
  #     else
  #       if (provisoner =~ ELASTIC_PROVISIONING_DRIVERS_REGEX) 
  #         Log.info {"provisioner production mode"}
  #         Log.info {"Provisoners: #{provisoners}"}
  #         elastic = true
  #       end
  #     end
  #   end
  #   Log.info {"elastic? #{elastic}"}
  #   elastic
  # end

  def self.storage_class_by_volumes(volumes, namespace : String? = nil)
    Log.info {"storage_class_by_volumes? "}
    Log.info {"storage_class_by_volumes? volumes: #{volumes}"}
    volume_claims = Volume.pvc_volumes(volumes)
    Log.info {"volume_claims #{volume_claims}"}
    storage_class_names = volume_claims.reduce( [] of Hash(String, JSON::Any)) do |acc, claim| 
      resource = begin
        KubectlClient::Get.resource("pvc", claim.dig?("persistentVolumeClaim", "claimName").to_s, namespace)
      rescue ex : KubectlClient::ShellCMD::NotFoundError
        Log.info { "PVC #{claim.dig?("persistentVolumeClaim", "claimName")} not found" }
        nil
      end
      Log.info {"pvc resource #{resource}"}

      if resource && resource.dig?("spec", "storageClassName")
        Log.info {"StorageClass: #{resource.dig?("spec", "storageClassName")}"}
        acc << { "claim_name" =>  claim.dig("persistentVolumeClaim", "claimName"), "class_name" => resource.dig("spec", "storageClassName") }
      else
        acc
      end
    end
    Log.info {"storage_class_names: #{storage_class_names}"}
    storage_class_names
  end
end
module StorageClass
  def self.elastic_by_storage_class?(storage_class_names : Array(Hash(String, JSON::Any)), 
                                     namespace : String? = nil) : {elastic: Bool, missing_classes: Array(String)}
    Log.info {"StorageClass.elastic_by_storage_class"}
    Log.for("elastic_volumes:storage_class_names").info { storage_class_names }

    #todo elastic_by_storage_class?
    elastic = false
    missing_classes = [] of String
    provisioners = storage_class_names.reduce( [] of String) do |acc, storage_class|
      resource = begin
        KubectlClient::Get.resource("storageclasses", storage_class.dig?("class_name").to_s, namespace)
      rescue ex : KubectlClient::ShellCMD::NotFoundError
        Log.info { "StorageClass #{storage_class.dig?("class_name")} not found, volume is not elastic" }
        missing_classes << storage_class.dig?("class_name").to_s
        nil
      end
      if resource && resource.dig?("provisioner")
        acc << resource.dig("provisioner").as_s 
      else
        acc
      end
    end

    Log.for("elastic_volumes:provisioners").info { provisioners }

    Log.info {"Provisioners: #{provisioners}"}
    provisioners.each do |provisioner|
      if ENV["CNTI_TESTSUITE_ENV"]? == "TEST"
        if (provisioner =~ ELASTIC_PROVISIONING_DRIVERS_REGEX_SPEC)
          Log.info {"provisioner test mode"}
          Log.info {"Elastic provisioner: #{provisioner}"}
          elastic = true
        end
      else
        if (provisioner =~ ELASTIC_PROVISIONING_DRIVERS_REGEX)
          Log.info {"provisioner production mode"}
          Log.info {"Elastic provisioner: #{provisioner}"}
          elastic = true
        end
      end
    end
    # A PVC whose StorageClass does not exist can never bind, so a missing
    # class always makes the workload non-elastic regardless of other PVCs.
    if missing_classes.any?
      Log.info {"StorageClass(es) #{missing_classes.join(", ")} not found, workload is not elastic"}
      elastic = false
    end
    Log.info {"elastic? #{elastic}"}
    {elastic: elastic, missing_classes: missing_classes}
  end
end

module VolumeClaimTemplate
  def self.pvc_name_by_vct_resource(resource) : String | Nil
    Log.info {"VolumeClaimTemplate.pvc_name_by_vct_resource"}
    resource_name = resource.dig("metadata", "name")
    vct = resource.dig?("spec", "volumeClaimTemplates")
    if vct && vct.size > 0
      #K8s only supports one volume claim template per resource
      vct_name = vct[0].dig?("metadata", "name")
      name = "#{vct_name}-#{resource_name}-0"
    end
    Log.for("VolumeClaimTemplate.pvc_name_by_vct_resource").info {"name: #{name}"}
    name
  end

  def self.vct_resource?(resource)
    Log.info {" vct_resource??"}
    Log.info {" vct_resource? resource: #{resource}"}
    vct = resource.dig?("spec", "volumeClaimTemplates")
    Log.info {" vct_resource? vct: #{vct}"}
    if vct && vct.size > 0
      true
    else
      false
    end
  end

  def self.storage_class_by_vct_resource(resource, namespace)
    Log.info {"storage_class_by_vct_resource"}
    pvc_name = VolumeClaimTemplate.pvc_name_by_vct_resource(resource)
    resource = begin
      KubectlClient::Get.resource("pvc", pvc_name.to_s, namespace)
    rescue ex : KubectlClient::ShellCMD::NotFoundError
      Log.info { "PVC #{pvc_name} not found" }
      nil
    end

    Log.info {"pvc resource #{resource}"}
    storage_class = nil

    if resource && resource.dig?("spec", "storageClassName")
      Log.info {"StorageClass: #{resource.dig?("spec", "storageClassName")}"}
      # { "claim_name" =>  claim.dig("persistentVolumeClaim", "claimName"), "class_name" => resource.dig("spec", "storageClassName") }
      storage_class = { "class_name" => resource.dig("spec", "storageClassName") }
    end
    Log.info {"storage_class: #{storage_class}"}
    storage_class
  end 
end

module WorkloadResource 
  include Volume
  include VolumeClaimTemplate

  def self.elastic?(resource, volumes, namespace : String? = nil) : {elastic: Bool, missing_classes: Array(String)}
    Log.info {"workloadresource elastic?"}
    missing_classes = [] of String
    if VolumeClaimTemplate.vct_resource?(resource)
      storage_class = VolumeClaimTemplate.storage_class_by_vct_resource(resource, namespace)
      if storage_class
        result = StorageClass.elastic_by_storage_class?([storage_class], namespace)
        elastic = result[:elastic]
        missing_classes = result[:missing_classes]
      else
        elastic = false
      end
    else
      result = Volume.elastic_by_volumes?(volumes, namespace)
      elastic = result[:elastic]
      missing_classes = result[:missing_classes]
    end
    Log.info {"workloadresource elastic?: #{elastic}"}
    {elastic: elastic, missing_classes: missing_classes}
  end
end

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
    volumes_used = false

    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, volumes|
      Log.for("elastic_volumes:test_resource").debug { resource.inspect }
      Log.for("elastic_volumes:volumes").debug { volumes.inspect }

      # Only persistent (PVC-backed) volumes are evaluated for elasticity. ConfigMap,
      # Secret and emptyDir volumes are not persistent storage and have nothing to check.
      # StatefulSets with volumeClaimTemplates are always evaluated via the VCT path.
      pvc_volumes = Volume.pvc_volumes(volumes.as_a)
      full_resource = KubectlClient::Get.resource(resource["kind"], resource["name"], resource["namespace"])
      next true if pvc_volumes.empty? && !VolumeClaimTemplate.vct_resource?(full_resource)
      volumes_used = true

      elastic_result = WorkloadResource.elastic?(full_resource, pvc_volumes, resource["namespace"])
      Log.for("#{t.name}:elastic_result").info {elastic_result}
      unless elastic_result[:elastic]
        reason = if elastic_result[:missing_classes].any?
                   "uses non-elastic volumes (missing storage class(es): #{elastic_result[:missing_classes].join(", ")}): #{pvc_volumes.map(&.dig("name")).join(", ")}"
                 else
                   "uses non-elastic volumes: #{pvc_volumes.map(&.dig("name")).join(", ")}"
                 end
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: reason)
      end
    
      elastic_result[:elastic]
    end

    Log.for("elastic_volumes:result").info { "Volumes used: #{volumes_used}; Elastic?: #{task_response}" }
    if !volumes_used
      result.na("No persistent volumes are used")
    elsif task_response
      result.passed("All used volumes are elastic")
    else
      result.failed("Some of the used volumes are not elastic")
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

desc "Does the CNF use a database which uses perisistence in a cloud native way"
scored_task "database_persistence",
  emoji: "🧫",
  fail: -1 do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    # Log.debug { "database_persistence" }
    # todo K8s Database persistence test: if a mysql (or any popular database) image is installed:
    non_elastic_database_statefulset_found = false
    match = Mysql.match
    Log.info {"database_persistence mysql: #{match}"}

    unless match && match[:found]
      result.na("CNF does not use database")
      next
    end

    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, volumes|
      # Skip resources that do not have containers with mysql image
      images = containers.as_a.map {|container| container["image"]}
      next true unless images.any? do |image| 
        Mysql::MYSQL_IMAGES.any? do |mysql_image|
          image.as_s.includes?(mysql_image) 
        end
      end
      # Skip non-statefulset resources
      next true if resource["kind"].downcase != "statefulset"

      namespace = resource["namespace"]
      Log.info {"database_persistence namespace: #{namespace}"}
      Log.info {"database_persistence resource: #{resource}"}
      Log.info {"database_persistence volumes: #{volumes}"}
      full_resource = KubectlClient::Get.resource(resource["kind"], resource["name"], namespace)
      pvc_volumes = Volume.pvc_volumes(volumes.as_a)
      elastic_result = WorkloadResource.elastic?(full_resource, pvc_volumes, namespace)
      Log.info {"database_persistence elastic_volume: #{elastic_result[:elastic]}"}

      unless elastic_result[:elastic]
        reason = if elastic_result[:missing_classes].any?
                   "uses non-elastic volumes (missing storage class(es): #{elastic_result[:missing_classes].join(", ")}): #{pvc_volumes.map(&.dig("name")).join(", ")}"
                 else
                   "uses non-elastic volumes: #{pvc_volumes.map(&.dig("name")).join(", ")}"
                 end
        result.add_impacted_resource("StatefulSet", resource["name"], resource["namespace"], reason: reason)
      end

      elastic_result[:elastic]
    end

    if task_response
      result.passed("CNF uses database with cloud-native persistence")
    else
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
