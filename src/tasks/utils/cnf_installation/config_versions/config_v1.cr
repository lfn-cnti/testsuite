require "./config_base.cr"


module CNFInstall
  module Config
    @[YAML::Serializable::Options(emit_nulls: true)]
    class ConfigV1 < ConfigBase
      getter config_version : String?
      getter destination_cnf_dir : String?
      getter source_cnf_dir : String?
      getter manifest_directory : String?
      getter helm_directory : String?
      getter release_name : String?
      getter helm_repository : HelmRepository?
      getter helm_chart : String?
      getter helm_values : String?
      getter helm_install_namespace : String?
      getter container_names : Array(Container)?
      getter white_list_container_names : Array(String)?
      getter docker_insecure_registries : Array(String)?
      getter image_registry_fqdns : Hash(String, String?)?
      
      # Unused properties
      getter install_script : String?
      getter service_name : String?
      getter git_clone_url : String?
      getter docker_repository : String?

      # 5G related properties
      getter amf_label : String?
      getter smf_label : String?
      getter upf_label : String?
      getter core : String?
      getter amf_service_name : String?
      getter mmc : String?
      getter mnc : String?
      getter sst : String?
      getter sd : String?
      getter tac : String?
      getter protectionScheme : String?
      getter publicKey : String?
      getter publicKeyId : String?
      getter routingIndicator : String?
      getter enabled : String?
      getter count : String?
      getter initialMSISDN : String?
      getter key : String?
      getter op : String?
      getter opType : String?
      getter type : String?
      getter apn : String?
      getter emergency : String?
  
      # Nested class for Helm Repository details
      class HelmRepository < ConfigBase
        getter name : String
        getter repo_url : String?
      end
  
      # Nested class for Container details
      class Container < ConfigBase
        getter name : String?
        getter rollback_from_tag : String?
        getter rolling_update_test_tag : String?
        getter rolling_downgrade_test_tag : String?
        getter rolling_version_change_test_tag : String?
      end
    end
  end
end
