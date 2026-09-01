require "../config_versions/config_versions.cr"

module CNFInstall
  module Config
    # Rules for configV1 to configV2 transformation
    class V1ToV2Transformation < TransformationBase
      def initialize(@input_config : ConfigV1)
        super()
      end

      def transform : YAML::Any
        output_config_hash = {
          "config_version" => "v2",
          "common" => transform_common,
          "deployments" => transform_deployments,
        }
      
        # Convert the entire native hash to stripped YAML::Any at the end.
        @output_config = process_data(output_config_hash).not_nil!
      end
      
      private def transform_common : Hash(String, Array(Hash(String, String | Nil)) | Array(String) | Hash(String, String | Nil))
        common = {} of String => Array(Hash(String, String | Nil)) | Array(String) | Hash(String, String | Nil)
      
        common = {
          "white_list_container_names" => @input_config.white_list_container_names,
          "docker_insecure_registries" => @input_config.docker_insecure_registries,
          "image_registry_fqdns" => @input_config.image_registry_fqdns,
          "container_names" => transform_container_names
        }.compact
      
        common
      end
      
      private def transform_container_names : Array(Hash(String, String | Nil))
        if @input_config.container_names
          containers = @input_config.container_names.not_nil!.map do |container|
            {
              "name" => container.name,
              "rollback_from_tag" => container.rollback_from_tag,
              "rolling_update_test_tag" => container.rolling_update_test_tag,
              "rolling_downgrade_test_tag" => container.rolling_downgrade_test_tag,
              "rolling_version_change_test_tag" => container.rolling_version_change_test_tag
            }
          end
  
          return containers
        end
  
        [] of Hash(String, String | Nil)
      end
      
      private def transform_deployments : Hash(String, Array(Hash(String, String | Nil)))
        deployments = {} of String => Array(Hash(String, String | Nil))
  
        if @input_config.manifest_directory
          deployments["manifests"] = [{
            "name" => @input_config.release_name,
            "manifest_directory" => @input_config.manifest_directory
          }]
        elsif @input_config.helm_directory
          deployments["helm_dirs"] = [{
            "name" => @input_config.release_name,
            "helm_directory" => @input_config.helm_directory,
            "helm_values" => @input_config.helm_values,
            "namespace" => @input_config.helm_install_namespace
          }]
        elsif @input_config.helm_chart
          helm_repo_name, helm_chart_name = @input_config.helm_chart.not_nil!.split("/", 2)
          helm_chart_data = {
            "name" => @input_config.release_name,
            "helm_chart_name" => helm_chart_name,
            "helm_repo_name" => helm_repo_name,
            "helm_values" => @input_config.helm_values,
            "namespace" => @input_config.helm_install_namespace
          }
        
          if @input_config.helm_repository
            helm_chart_data["helm_repo_url"] = @input_config.helm_repository.not_nil!.repo_url
          end
        
          deployments["helm_charts"] = [helm_chart_data]
        end
      
        deployments
      end
      
    end
  end
end