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
  def self.elastic_by_volumes?(volumes : Array(JSON::Any), namespace : String? = nil)
    Log.info {"Volume.elastic_by_volumes"}
    storage_class_names = storage_class_by_volumes(volumes, namespace)
    elastic = StorageClass.elastic_by_storage_class?(storage_class_names, namespace)
    Log.info {"Volume.elastic_by_volumes elastic: #{elastic}"}
    elastic
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
  #     if ENV["CNF_TESTSUITE_ENV"]? == "TEST"
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
    volume_claims = volumes.select{ |x| x.dig?("persistentVolumeClaim", "claimName") } 
    Log.info {"volume_claims #{volume_claims}"}
    storage_class_names = volume_claims.reduce( [] of Hash(String, JSON::Any)) do |acc, claim| 
      resource = KubectlClient::Get.resource("pvc", claim.dig?("persistentVolumeClaim", "claimName").to_s, namespace)
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
                                     namespace : String? = nil)
    Log.info {"StorageClass.elastic_by_storage_class"}
    Log.for("elastic_volumes:storage_class_names").info { storage_class_names }

    #todo elastic_by_storage_class?
    elastic = false
    provisioners = storage_class_names.reduce( [] of String) do |acc, storage_class|
      resource = KubectlClient::Get.resource("storageclasses", storage_class.dig?("class_name").to_s, namespace)
      if resource.dig?("provisioner")
        acc << resource.dig("provisioner").as_s 
      else
        acc
      end
    end

    Log.for("elastic_volumes:provisioners").info { provisioners }

    Log.info {"Provisioners: #{provisioners}"}
    provisioners.each do |provisioner|
      if ENV["CNF_TESTSUITE_ENV"]? == "TEST"
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
    Log.info {"elastic? #{elastic}"}
    elastic
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
    resource = KubectlClient::Get.resource("pvc", pvc_name.to_s, namespace)

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

  def self.elastic?(resource, volumes, namespace : String? = nil)
    Log.info {"workloadresource elastic?"}
    elastic = false
    if VolumeClaimTemplate.vct_resource?(resource)
      storage_class = VolumeClaimTemplate.storage_class_by_vct_resource(resource, namespace)
      if storage_class
        elastic = StorageClass.elastic_by_storage_class?([storage_class], namespace)
      end
    else
      elastic = Volume.elastic_by_volumes?(volumes, namespace)
    end
    Log.info {"workloadresource elastic?: #{elastic}"}
    elastic
  end
end

desc "Does the CNF crash when node-drain occurs"
scored_task "node_drain",
  type: CNFManager::TestType::Essential,
  deps: ["setup:install_litmus"],
  emoji: "🗡️💀♻" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    skip_reason : String? = nil
    task_response = CNFManager.workload_resource_test(args, config) do |resource, _, _|
      test_passed = true
      app_namespace = resource[:namespace]
      Log.info { "Current Resource Name: #{resource["kind"]}/#{resource["name"]} Namespace: #{resource["namespace"]}" }
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])

      # Check if labels exist before proceeding
      if spec_labels.as_h.size == 0
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "no resource label found for #{t.name} test")
        test_passed = false
      else
        schedulable_nodes = KubectlClient::Get.schedulable_nodes_list
        # The whole selector: one label of a multi-label selector (every Helm
        # chart's) also matches other releases of the same chart.
        app_label = spec_labels.as_h.map { |key, value| "#{key}=#{value}" }.join(",")

        # Declare this outside the block so that the name of the node can be used to uncordon later.
        cordon_target_node_name = nil

        begin
          # Resolve the workload's node once, up front, and use that single answer for
          # both the cordon and the chaos experiment. Asking a second time after
          # cordoning let the two answers disagree: pods terminating from an earlier
          # test are still listed by kubectl, so the first answer could name a node the
          # workload had already left, and the run would cordon one node while draining
          # another.
          app_node_name = LitmusManager.get_workload_node_name(app_label, namespace: app_namespace)

          if schedulable_nodes.size <= 1
            skip_reason = "node_drain chaos test requires the cluster to have atleast two schedulable nodes"
          elsif app_node_name.nil?
            skip_reason = "node_drain chaos test found no scheduled pod for #{app_label} in the #{app_namespace} namespace"
          else
            Log.info { "Found node to cordon #{app_node_name} using selector #{app_label} in #{app_namespace} namespace." }

            # Record the cordon target before cordoning, so the ensure block below
            # releases the node even if the cordon only partly took effect.
            cordon_target_node_name = app_node_name
            cordon_result = KubectlClient::Utils.cordon(app_node_name)

            # If cordoning fails, skip the test.
            if cordon_result[:status].success?
              Log.info { "Cordoned node #{app_node_name} successfully." }
            else
              skip_reason = "node_drain chaos test was unable to cordon node #{app_node_name}"
            end
          end

          if skip_reason.nil? && app_node_name
            litmus_node_name = LitmusManager.get_litmus_node_name
            Log.info { "Workload Node Name: #{app_node_name}" }
            Log.info { "Litmus Node Name: #{litmus_node_name}" }

            if litmus_node_name == app_node_name
              # Litmus would be drained along with the workload, so it has to move
              # first. The workload's node is cordoned by now and is therefore already
              # absent from the schedulable list.
              Log.info { "Litmus and the workload are scheduled to the same node. Re-scheduling Litmus" }
              litmus_nodes = KubectlClient::Get.schedulable_nodes_list.compact_map do |item|
                item.dig?("metadata", "labels", LitmusManager::NODE_LABEL).try(&.as_s)
              end.reject { |node_name| node_name == app_node_name }
              Log.info { "Schedulable Litmus Nodes: #{litmus_nodes}" }

              litmus_target_node = litmus_nodes.first?
              if litmus_target_node.nil?
                # Nowhere to move Litmus to. Draining this node would take the chaos
                # operator down with the workload, so there is no test to run.
                skip_reason = "node_drain chaos test requires a schedulable node that does not run Litmus, but #{app_node_name} is the only one left"
              else
                download_file(LitmusManager::LITMUS_OPERATOR, LitmusManager.downloaded_operator_file)
                Log.info { "Re-Schedule Litmus" }
                LitmusManager.add_node_selector(litmus_target_node)
                KubectlClient::Apply.file(LitmusManager.modified_operator_file)
                KubectlClient::Wait.resource_wait_for_install(kind: "Deployment", resource_name: "chaos-operator-ce", wait_count: 180, namespace: "litmus")
              end
            end
          end

          if skip_reason.nil? && app_node_name
            LitmusManager.install_fault("node-drain", app_namespace, t.name)

            KubectlClient::Utils.annotate(resource["kind"], resource["name"], ["litmuschaos.io/chaos=\"true\""], namespace: app_namespace)

            chaos_experiment_name = "node-drain"
            test_name = "#{resource["name"]}-#{Random::Secure.hex(4)}"
            chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

            template = ChaosTemplates::NodeDrain.new(
              test_name,
              "#{chaos_experiment_name}",
              app_namespace,
              app_label,
              app_node_name
            ).to_s
            Log.for("node_drain").info { "Chaos test name: #{test_name}; Experiment name: #{chaos_experiment_name}; Selector #{app_label}; namespace: #{app_namespace}" }
            chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
            File.write(chaos_template_path, template)
            KubectlClient::Apply.file(chaos_template_path)
            LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
            test_passed = LitmusManager.check_chaos_verdict(chaos_result_name, chaos_experiment_name, args, namespace: app_namespace, result: result)
            unless test_passed
              # The verdict says the workload did not come back; say where it stands.
              why = WorkloadDiagnostics.report(result, resource["kind"], resource["name"], app_namespace, "#{resource["kind"]}/#{resource["name"]} after draining #{app_node_name} for #{NODE_DRAIN_TOTAL_CHAOS_DURATION}s")
              result.add_impacted_resource(resource["kind"], resource["name"], app_namespace,
                reason: "did not recover from draining node #{app_node_name}#{why.first?.try { |w| ": #{w}" }}")
            end
          end
        ensure
          # Uncordon the node whatever happened above. Without this, a test that raises
          # leaves the cluster one schedulable node short for every test that follows.
          if cordon_target_node_name
            uncordon_result = KubectlClient::Utils.uncordon("#{cordon_target_node_name}")

            # If uncordoning fails, log the error.
            if uncordon_result[:status].success?
              Log.info { "Uncordoned node #{cordon_target_node_name} successfully." }
            else
              Log.error { "Uncordoning node #{cordon_target_node_name} failed." }
              skip_reason = "node_drain chaos test was unable to uncordon node #{cordon_target_node_name}"
            end
          end
        end
      end

      test_passed
    end
    if skip_reason
      Log.for(t.name).warn { "#{skip_reason}. Current number of schedulable nodes: #{KubectlClient::Get.schedulable_nodes_list.size}" }
      result.skipped(skip_reason)
    elsif task_response
      result.passed("node_drain chaos test passed")
    else
      result.failed("node_drain chaos test failed")
    end
  end
end

desc "Does the CNF use an elastic persistent volume"
scored_task "elastic_volumes",
  type: CNFManager::TestType::Bonus,
  emoji: "🧫" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config, result|
    all_volumes_elastic = true
    volumes_used = false

    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, _, volumes|
      Log.for("elastic_volumes:test_resource").debug { resource.inspect }
      Log.for("elastic_volumes:volumes").debug { volumes.inspect }

      next true if volumes.size == 0
      volumes_used = true

      # todo use workload resource
      # elastic = WorkloadResource.elastic?(volumes)

      full_resource = KubectlClient::Get.resource(resource["kind"], resource["name"], resource["namespace"])
      elastic_result = WorkloadResource.elastic?(full_resource, volumes.as_a, resource["namespace"])
      Log.for("#{t.name}:elastic_result").info {elastic_result}
      unless elastic_result
        result.add_impacted_resource(resource["kind"], resource["name"], resource["namespace"], reason: "uses non-elastic volumes: #{volumes.as_a.map(&.dig("name")).join(", ")}")
      end
    
      elastic_result
    end

    Log.for("elastic_volumes:result").info { "Volumes used: #{volumes_used}; Elastic?: #{all_volumes_elastic}" }
    if !volumes_used
      result.skipped("No volumes are used")
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
      result.skipped("CNF does not use database")
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
      elastic_volume = WorkloadResource.elastic?(full_resource, volumes.as_a, namespace)
      Log.info {"database_persistence elastic_volume: #{elastic_volume}"}

      unless elastic_volume
        result.add_impacted_resource("StatefulSet", resource["name"], resource["namespace"], reason: "uses non-elastic volumes: #{volumes.as_a.map(&.dig("name")).join(", ")}")
      end

      elastic_volume
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
    task_response = CNFManager.cnf_workload_resources(args, config) do | resource|
      hostPath_found = nil 
      begin
        # Note: A storageClassName value of "local-storage" is insufficient to determine if the
        # persistent volume is indeed local storage.  This is because the storageClass can be redefined
        # to be anything (e.g. the name local-storage can be redefined to be block storage behind the scenes) 

        volumes = [] of YAML::Any
        if resource["spec"].as_h["template"].as_h["spec"].as_h["volumes"]?
            volumes = resource["spec"].as_h["template"].as_h["spec"].as_h["volumes"].as_a 
        end
        Log.for(t.name).debug { "volumes: #{volumes}" }
        persistent_volume_claim_names = volumes.map do |volume|
          # get persistent volume claim that matches persistent volume claim name
          if volume.as_h["persistentVolumeClaim"]? && volume.as_h["persistentVolumeClaim"].as_h["claimName"]?
              volume.as_h["persistentVolumeClaim"].as_h["claimName"]
          else
            nil 
          end
        end.compact
        Log.for(t.name).debug { "persistent volume claim names: #{persistent_volume_claim_names}" }

        # TODO (optional) check storage class of persistent volume claim
        # loop through all pvc names
        # get persistent volume that matches pvc name
        # get all items, get spec, get claimRef, get pvc name that matches pvc name 
        local_storage_not_found = true 
        persistent_volume_claim_names.map do | claim_name|
          items = KubectlClient::Get.pv_items_by_claim_name(claim_name.as_s)
          items.map do |item|
            begin
              if item["spec"]["local"]? && item["spec"]["local"]["path"]?
                  local_storage_not_found = false 
              end
            rescue ex
              Log.for(t.name).info { ex.message }
              local_storage_not_found = true 
            end
          end
        end
      rescue ex
        Log.for(t.name).error { ex.message }
        result.append_description("Rescued: On resource #{resource["metadata"]["name"]?} of kind #{resource["kind"]}, local storage configuration volumes not found")
        local_storage_not_found = true
      end
      local_storage_not_found
    end

    if task_response.any?(false)
      result.failed("local storage configuration volumes found (ভ_ভ) ރ")
    else
      result.passed("local storage configuration volumes not found 🖥️")
    end
  end
end
