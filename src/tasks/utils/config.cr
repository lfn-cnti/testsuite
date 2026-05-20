require "totem"
require "colorize"
require "./types/cnf_conformance_yml_type.cr"
require "./helm.cr"
require "uuid"
require "./points.cr"
require "./task.cr"

module CNFManager 

  class Config
    def initialize(cnf_config)
      @cnf_config = cnf_config 
    end
    property cnf_config : NamedTuple(destination_cnf_dir: String,
                                     source_cnf_file: String,
                                     source_cnf_dir: String,
                                     yml_file_path: String,
                                     install_method: Tuple(Symbol, String),
                                     manifest_directory: String,
                                     helm_directory: String, 
                                     helm_chart_path: String, 
                                     manifest_file_path: String, 
                                     git_clone_url: String,
                                     install_script: String,
                                     release_name: String,
                                     service_name:  String,
                                     docker_repository: String,
                                     helm_repository: NamedTuple(name:  String, 
                                                                 repo_url:  String) | Nil,
                                     helm_chart:  String,
                                     helm_chart_container_name: String,
                                     rolling_update_tag: String,
                                     container_names: Array(Hash(String, String )) | Nil,
                                     white_list_container_names: Array(String)) 

    def self.parse_config_yml(config_yml_path : String) : CNFManager::Config
      LOGGING.debug "parse_config_yml config_yml_path: #{config_yml_path}"
      yml_file = CNFManager.ensure_cnf_conformance_yml_path(config_yml_path)
      #TODO modify the destination conformance yml instead of the source conformance yml 
      # (especially in the case of the release manager).  Then reread the destination config
      # TODO for cleanup, read source, then find destination and use release name from destination config
      # TODO alternatively use a CRD to save the release name
      config = CNFManager.parsed_config_file(yml_file)

      install_method = CNFManager.cnf_installation_method(config)

      CNFManager.generate_and_set_release_name(config_yml_path)

      destination_cnf_dir = CNFManager.cnf_destination_dir(yml_file)

      yml_file_path = CNFManager.ensure_cnf_conformance_dir(config_yml_path)
      source_cnf_file = yml_file
      source_cnf_dir = yml_file_path
      manifest_directory = optional_key_as_string(config, "manifest_directory")
      if config["helm_repository"]?
          helm_repository = config["helm_repository"].as_h
        helm_repo_name = optional_key_as_string(helm_repository, "name")
        helm_repo_url = optional_key_as_string(helm_repository, "repo_url")
      else
        helm_repo_name = ""
        helm_repo_url = ""
      end
      helm_chart = optional_key_as_string(config, "helm_chart")
      release_name = optional_key_as_string(config, "release_name")
      service_name = optional_key_as_string(config, "service_name")
      helm_directory = optional_key_as_string(config, "helm_directory")
      git_clone_url = optional_key_as_string(config, "git_clone_url")
      install_script = optional_key_as_string(config, "install_script")
      docker_repository = optional_key_as_string(config, "docker_repository")
      if helm_directory.empty?
        working_chart_directory = "exported_chart"
      else
        working_chart_directory = helm_directory
      end
      helm_chart_path = CNFManager.helm_dir_path(destination_cnf_dir, working_chart_directory) 
      manifest_file_path = destination_cnf_dir + "/" + "temp_template.yml"
      white_list_container_names = optional_key_as_string(config, "allowlist_helm_chart_container_names")
      if config["allowlist_helm_chart_container_names"]?
        white_list_container_names = config["allowlist_helm_chart_container_names"].as_a.map do |c|
          "#{c.as_s?}"
        end
      else
        white_list_container_names = [] of String
      end
      if config["container_names"]?
        container_names_totem = config["container_names"]
        container_names = container_names_totem.as_a.map do |container|
          {"name" => optional_key_as_string(container, "name"),
           "rolling_update_test_tag" => optional_key_as_string(container, "rolling_update_test_tag"),
           "rolling_downgrade_test_tag" => optional_key_as_string(container, "rolling_downgrade_test_tag"),
           "rolling_version_change_test_tag" => optional_key_as_string(container, "rolling_version_change_test_tag"),
           "rollback_from_tag" => optional_key_as_string(container, "rollback_from_tag"),
           }
        end
      else
        container_names = [{"name" => "",
         "rolling_update_test_tag" => "",
         "rolling_downgrade_test_tag" => "",
         "rolling_version_change_test_tag" => "",
         "rollback_from_tag" => "",
         }]
      end

      new({ destination_cnf_dir: destination_cnf_dir,
                               source_cnf_file: source_cnf_file,
                               source_cnf_dir: source_cnf_dir,
                               yml_file_path: yml_file_path,
                               install_method: install_method,
                               manifest_directory: manifest_directory,
                               helm_directory: helm_directory, 
                               helm_chart_path: helm_chart_path, 
                               manifest_file_path: manifest_file_path,
                               git_clone_url: git_clone_url,
                               install_script: install_script,
                               release_name: release_name,
                               service_name: service_name,
                               docker_repository: docker_repository,
                               helm_repository: {name: helm_repo_name, repo_url: helm_repo_url},
                               helm_chart: helm_chart,
                               helm_chart_container_name: "",
                               rolling_update_tag: "",
                               container_names: container_names,
                               white_list_container_names: white_list_container_names })

    end
  end
end
