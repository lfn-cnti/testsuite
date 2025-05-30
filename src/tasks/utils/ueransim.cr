require "../../modules/cluster_tools"
module UERANSIM 

  def self.uninstall
    Log.debug { "uninstall_ueransim" } 
    Helm.uninstall("ueransim", "testsuite-5g")
  end

  def self.install(config)
    Log.info {"Installing ueransim with 5g config"}
    core = config.common.five_g_parameters.amf_label 
    Log.info { "core: #{core}" }
    #todo use sane defaults (i.e. search for amf, upf, etc in pod names) if no 5gcore labels are present
    amf_service_name = config.common.five_g_parameters.amf_service_name 
    mmc = config.common.five_g_parameters.mmc 
    mnc = config.common.five_g_parameters.mnc 
    sst = config.common.five_g_parameters.sst 
    sd = config.common.five_g_parameters.sd 
    tac = config.common.five_g_parameters.tac 
    enabled = config.common.five_g_parameters.enabled 
    count = config.common.five_g_parameters.count 
    initialMSISDN = config.common.five_g_parameters.initialMSISDN 
    key = config.common.five_g_parameters.key 
    op = config.common.five_g_parameters.op 
    opType = config.common.five_g_parameters.opType 
    type = config.common.five_g_parameters.type 
    apn = config.common.five_g_parameters.apn 
    emergency = config.common.five_g_parameters.emergency 

    if core 
      ueran_pods = KubectlClient::Get.pods_by_nodes(KubectlClient::Get.schedulable_nodes_list, label: {"app.kubernetes.io/name" => "ueransim-gnb"})

      Log.info { "ueran_pods: #{ueran_pods}" }
      unless ueran_pods[0]? == nil
        Log.info { "Found ueransim ... deleting" }
        Helm.uninstall("ueransim", "testsuite-5g")
      end
      Helm.pull_oci("oci://registry-1.docker.io/gradiant/ueransim-gnb", version: "0.2.5")

      protectionScheme = config.common.five_g_parameters.protectionScheme
      unless protectionScheme.nil? || protectionScheme.empty?
        protectionScheme = "protectionScheme: #{protectionScheme}"
      end
      publicKey = config.common.five_g_parameters.publicKey
      unless publicKey.nil? || publicKey.empty?
        publicKey = "publicKey: '#{publicKey}'"
      end
      publicKeyId = config.common.five_g_parameters.publicKeyId 
      unless publicKeyId.nil? || publicKeyId.empty?
        publicKeyId = "publicKeyId: #{publicKeyId}"
      end
      routingIndicator = config.common.five_g_parameters.routingIndicator
      unless routingIndicator.nil? || routingIndicator.empty?
        routingIndicator = "routingIndicator: '#{routingIndicator}'"
      end

      ue_values = UERANSIM::Template.new(amf_service_name,
                                         mmc,
                                         mnc,
                                         sst,
                                         sd,
                                         tac,
                                         protectionScheme,
                                         publicKey,
                                         publicKeyId,
                                         routingIndicator,
                                         enabled,
                                         count,
                                         initialMSISDN,
                                         key,
                                         op,
                                         opType,
                                         type,
                                         apn,
                                         emergency 
                                        ).to_s
      Log.info { "ue_values: #{ue_values}" }
      File.write("gnb-ues-values.yaml", ue_values)
      # File.write("gnb-ues-values.yaml", UES_VALUES)
      File.write("#{Dir.current}/ueransim-gnb/resources/ue.yaml", UERANSIM_HELMCONFIG)
      CNFManager.ensure_namespace_exists!("testsuite-5g")
      Helm.install("ueransim", "#{Dir.current}/ueransim-gnb", namespace: "testsuite-5g", values: "--values ./gnb-ues-values.yaml")
      Log.info { "after helm install" }
      KubectlClient::Wait.resource_wait_for_install("Pod", "ueransim", namespace: "testsuite-5g")
      true
    else
      false
      puts "You must set the core label for your AMF node".colorize(:red)
    end
  end

  class Template 
    # The argument for insecure_registries is a string
    # because the template only writes the content
    # and expects a list of comma separated strings.
    def initialize(@amf_service_name : String,
                   @mmc : String,
                   @mnc : String,
                   @sst : String,
                   @sd : String,
                   @tac : String,
                   @protectionScheme : String,
                   @publicKey : String,
                   @publicKeyId : String,
                   @routingIndicator : String,
                   @enabled : String,
                   @count : String,
                   @initialMSISDN : String,
                   @key : String,
                   @op : String,
                   @opType : String,
                   @type : String,
                   @apn : String,
                   @emergency : String
                  )
    end
    ECR.def_to_s("src/templates/ues-values-template.yml.ecr")
  end


end

