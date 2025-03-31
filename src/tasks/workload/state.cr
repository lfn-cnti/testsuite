# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "kubectl_client"

desc "The CNF test suite checks if state is stored in a custom resource definition or a separate database (e.g. etcd) rather than requiring local storage.  It also checks to see if state is resilient to node failure"
task "state", ["no_local_volume_configuration", "elastic_volumes", "database_persistence", "node_drain"] do |_, args|
  stdout_score("state")
  case "#{ARGV.join(" ")}" 
  when /state/
    stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
  end
end

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
  #     if ENV["CRYSTAL_ENV"]? == "TEST"
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
      if ENV["CRYSTAL_ENV"]? == "TEST"
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
task "node_drain", ["install_litmus"] do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    skipped = false
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|
      app_namespace = resource[:namespace]
      Log.info { "Current Resource Name: #{resource["kind"]}/#{resource["name"]} Namespace: #{resource["namespace"]}" }
      spec_labels = KubectlClient::Get.resource_spec_labels(resource["kind"], resource["name"], resource["namespace"])

      schedulable_nodes_count=KubectlClient::Get.schedulable_nodes_list
      cordon_deployment_label = "#{spec_labels.as_h.first_key}"
      cordon_deployment_value = "#{spec_labels.as_h.first_value}"

      # Declare this outside the block so that the name of the node can be used to uncordon later.
      cordon_target_node_name = nil

      if schedulable_nodes_count.size > 1
        # Identify cordon node target.
        cordon_target_node_name = LitmusManager.get_target_node_to_cordon(cordon_deployment_label, cordon_deployment_value, namespace: app_namespace)
        Log.info { "Found node to cordon #{cordon_target_node_name} using label #{cordon_deployment_label}='#{cordon_deployment_value}' in #{app_namespace} namespace." }

        # Cordon the node.
        result = KubectlClient::Utils.cordon("#{cordon_target_node_name}")

        # If cordoning fails, skip the test.
        if result[:status].success?
          Log.info { "Cordoned node #{cordon_target_node_name} successfully." }
        else
          Log.info { "Unable to cordon node #{cordon_target_node_name}." }
          skipped = true
        end
      else
        Log.info { "Skipping test. Scheduleable node count is not > 1." }
        skipped = true
      end

      unless skipped
        if spec_labels.as_h.size > 0
          test_passed = true
        else
          stdout_failure("No resource label found for #{t.name} test for resource: #{resource["kind"]}/#{resource["name"]} in #{resource["namespace"]} namespace")
          test_passed = false
        end
        if test_passed
          deployment_label="#{spec_labels.as_h.first_key}"
          deployment_label_value="#{spec_labels.as_h.first_value}"
          app_nodeName_cmd = "kubectl get pods -l #{deployment_label}=#{deployment_label_value} -n #{resource["namespace"]} -o=jsonpath='{.items[0].spec.nodeName}'"
          Log.for("node_drain").debug { "Getting the app node name #{app_nodeName_cmd}" }
          status_code = Process.run("#{app_nodeName_cmd}", shell: true, output: appNodeName_response = IO::Memory.new, error: stderr = IO::Memory.new).exit_status
          Log.for("node_drain").debug { "status_code: #{status_code}" }
          app_nodeName = appNodeName_response.to_s

          litmus_nodeName_cmd = "kubectl get pods -n litmus -l app.kubernetes.io/name=litmus -o=jsonpath='{.items[0].spec.nodeName}'"
          Log.for("node_drain").debug { "Getting the app node name #{litmus_nodeName_cmd}" }
          status_code = Process.run("#{litmus_nodeName_cmd}", shell: true, output: litmusNodeName_response = IO::Memory.new, error: stderr = IO::Memory.new).exit_status
          Log.for("node_drain").debug { "status_code: #{status_code}" }
          litmus_nodeName = litmusNodeName_response.to_s
          Log.info { "Workload Node Name: #{app_nodeName}" }
          Log.info { "Litmus Node Name: #{litmus_nodeName}" }
          if litmus_nodeName == app_nodeName
            Log.info { "Litmus and the workload are scheduled to the same node. Re-scheduling Litmus" }
            nodes = KubectlClient::Get.schedulable_nodes_list
            node_names = nodes.map { |item|
              Log.info { "items labels: #{item.dig?("metadata", "labels")}" }
              node_name = item.dig?("metadata", "labels", "kubernetes.io/hostname")
              Log.debug { "NodeName: #{node_name}" }
              node_name
            }
            Log.info { "All Schedulable Nodes: #{nodes}" }
            Log.info { "Schedulable Node Names: #{node_names}" }
            litmus_nodes = node_names - ["#{litmus_nodeName}"]
            Log.info { "Schedulable Litmus Nodes: #{litmus_nodes}" }

            download("#{LitmusManager::LITMUS_OPERATOR}","#{LitmusManager::DOWNLOADED_LITMUS_FILE}")
            Log.info {"Re-Schedule Litmus"}
            LitmusManager.add_node_selector(litmus_nodes[0])
            KubectlClient::Apply.file("#{LitmusManager::MODIFIED_LITMUS_FILE}")
            KubectlClient::Wait.resource_wait_for_install(kind: "Deployment", resource_name: "chaos-operator-ce", wait_count: 180, namespace: "litmus")
          end

          experiment_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::Version}/faults/kubernetes/node-drain/fault.yaml"
          rbac_url = "https://raw.githubusercontent.com/litmuschaos/chaos-charts/#{LitmusManager::RBAC_VERSION}/charts/generic/node-drain/rbac.yaml"

          experiment_path = LitmusManager.download_template(experiment_url, "#{t.name}_experiment.yaml")
          KubectlClient::Apply.file(experiment_path, namespace: app_namespace)
  
          rbac_path = LitmusManager.download_template(rbac_url, "#{t.name}_rbac.yaml")
          rbac_yaml = File.read(rbac_path)
          rbac_yaml = rbac_yaml.gsub("namespace: default", "namespace: #{app_namespace}")
          File.write(rbac_path, rbac_yaml)
          KubectlClient::Apply.file(rbac_path)

          KubectlClient::Utils.annotate("deployment", resource["name"], "litmuschaos.io/chaos=\"true\"")

          chaos_experiment_name = "node-drain"
          test_name = "#{resource["name"]}-#{Random::Secure.hex(4)}"
          chaos_result_name = "#{test_name}-#{chaos_experiment_name}"

          template = ChaosTemplates::NodeDrain.new(
            test_name,
            "#{chaos_experiment_name}",
            app_namespace,
            "#{deployment_label}",
            "#{deployment_label_value}",
            app_nodeName
          ).to_s
          Log.for("node_drain").info { "Chaos test name: #{test_name}; Experiment name: #{chaos_experiment_name}; Label #{deployment_label}=#{deployment_label_value}; namespace: #{app_namespace}" }
          chaos_template_path = File.join(CNF_TEMP_FILES_DIR, "#{chaos_experiment_name}-chaosengine.yml")
          File.write(chaos_template_path, template)
          KubectlClient::Apply.file(chaos_template_path)
          LitmusManager.wait_for_test(test_name, chaos_experiment_name, args, namespace: app_namespace)
          test_passed = LitmusManager.check_chaos_verdict(chaos_result_name,chaos_experiment_name,args, namespace: app_namespace)
        end

        # Uncordon the node.
        result = KubectlClient::Utils.uncordon("#{cordon_target_node_name}")

        # If uncordoning fails, log the error.
        if result[:status].success?
          Log.info { "Uncordoned node #{cordon_target_node_name} successfully." }
        else
          Log.error { "Uncordoning node #{cordon_target_node_name} failed." }
          skipped = true
        end
      end

      test_passed
    end
    if skipped
      Log.for(t.name).warn{"The node_drain test needs minimum 2 schedulable nodes, current number of nodes: #{KubectlClient::Get.schedulable_nodes_list.size}"}
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "node_drain chaos test requires the cluster to have atleast two schedulable nodes")
    elsif task_response
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "node_drain chaos test passed")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "node_drain chaos test failed")
    end
  end
end

desc "Does the CNF use an elastic persistent volume"
task "elastic_volumes" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    all_volumes_elastic = true
    volumes_used = false
    task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, volumes, initialized|
      Log.for("elastic_volumes:test_resource").info { resource.inspect }
      Log.for("elastic_volumes:volumes").info { volumes.inspect }

      next if volumes.size == 0
      volumes_used = true

      # todo use workload resource
      # elastic = WorkloadResource.elastic?(volumes)

      full_resource = KubectlClient::Get.resource(resource["kind"], resource["name"], resource["namespace"])
      elastic_result = WorkloadResource.elastic?(full_resource, volumes.as_a, resource["namespace"])
      Log.for("#{t.name}:elastic_result").info {elastic_result}
      unless elastic_result
        all_volumes_elastic = false
      end
    end

    Log.for("elastic_volumes:result").info { "Volumes used: #{volumes_used}; Elastic?: #{all_volumes_elastic}" }
    if volumes_used == false
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "No volumes are used")
    elsif all_volumes_elastic
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "All used volumes are elastic")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "Some of the used volumes are not elastic")
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
task "database_persistence" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
    # Log.debug { "database_persistence" }
    # todo K8s Database persistence test: if a mysql (or any popular database) image is installed:
    statefulset_found = false
    non_elastic_database_statefulset_found = false
    match = Mysql.match
    Log.info {"database_persistence mysql: #{match}"}
    if match && match[:found]
      task_response = CNFManager.workload_resource_test(args, config, check_containers: false) do |resource, containers, volumes, initialized|
        # Skip resources that do not have containers with mysql image
        images = containers.as_a.map {|container| container["image"]}
        next unless images.any? do |image| 
          Mysql::MYSQL_IMAGES.any? do |mysql_image|
            image.as_s.includes?(mysql_image) 
          end
        end
        # Skip non-statefulset resources
        next if resource["kind"].downcase != "statefulset"
        
        statefulset_found = true
        namespace = resource["namespace"]
        Log.info {"database_persistence namespace: #{namespace}"}
        Log.info {"database_persistence resource: #{resource}"}
        Log.info {"database_persistence volumes: #{volumes}"}
        full_resource = KubectlClient::Get.resource(resource["kind"], resource["name"], namespace)
        elastic_volume = WorkloadResource.elastic?(full_resource, volumes.as_a, namespace)
        Log.info {"database_persistence elastic_volume: #{elastic_volume}"}
        unless elastic_volume
          non_elastic_database_statefulset_found = true
        end
      end
      if statefulset_found && !non_elastic_database_statefulset_found
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Pass5, "CNF uses database with cloud-native persistence")
      else
        CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "CNF uses database without cloud-native persistence (ভ_ভ) ރ 💾")
      end
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Skipped, "CNF does not use database")
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
task "no_local_volume_configuration" do |t, args|
  CNFManager::Task.task_runner(args, task: t) do |args, config|
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
        puts "Rescued: On resource #{resource["metadata"]["name"]?} of kind #{resource["kind"]}, local storage configuration volumes not found".colorize(:yellow)
        local_storage_not_found = true
      end
      local_storage_not_found
    end

    if task_response.any?(false)
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Failed, "local storage configuration volumes found (ভ_ভ) ރ")
    else
      CNFManager::TestCaseResult.new(CNFManager::ResultStatus::Passed, "local storage configuration volumes not found 🖥️")
    end
  end
end
