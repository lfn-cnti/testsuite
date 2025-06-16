require "./config_base.cr"


module CNFInstall
  module ConfigV2
    @[YAML::Serializable::Options(emit_nulls: true)]
    alias AnyDeploymentConfig = HelmChartConfig | HelmDirectoryConfig | ManifestDirectoryConfig

    class Config < CNFInstall::Config::ConfigBase
      getter config_version : String,
             common = CommonParameters.new(),
             deployments : DeploymentsConfig
    end

    class CommonParameters < CNFInstall::Config::ConfigBase
      getter container_names = [] of ContainerParameters,
             white_list_container_names = [] of String,
             docker_insecure_registries = [] of String,
             image_registry_fqdns = {} of String => String,
             five_g_parameters = FiveGParameters.new(),
             hardcoded_ip_exceptions = [] of HardcodedIPsAllowed
      def initialize()
      end
    end

    class DeploymentsConfig < CNFInstall::Config::ConfigBase
      getter helm_charts = [] of HelmChartConfig,
             helm_dirs = [] of HelmDirectoryConfig,
             manifests = [] of ManifestDirectoryConfig

      def after_initialize
        if @helm_charts.empty? && @helm_dirs.empty? && @manifests.empty?
          raise YAML::Error.new("At least one deployment should be configured")
        end


        deployment_names = Set(String).new
        {@helm_charts, @helm_dirs, @manifests}.each do |deployment_array|
          if deployment_array && !deployment_array.empty?
            
            deployment_array.each do |deployment|
              if deployment_names.includes?(deployment.name)
                raise YAML::Error.new("Deployment names should be unique: \"#{deployment.name}\"")
              else
                deployment_names.add(deployment.name)
              end
            end
          end
        end
      end
    end

    class DeploymentConfig < CNFInstall::Config::ConfigBase
      getter name : String,
             priority = 0
    end

    class HelmDeploymentConfig < DeploymentConfig
      getter helm_values = "",
             namespace = ""
    end

    class HelmChartConfig < HelmDeploymentConfig
      getter helm_repo_name : String,
             helm_chart_name : String,
             helm_repo_url = ""
    end

    class HelmDirectoryConfig < HelmDeploymentConfig
      getter helm_directory : String
    end

    class ManifestDirectoryConfig < DeploymentConfig
      getter manifest_directory : String
    end

    class FiveGParameters < CNFInstall::Config::ConfigBase
      getter amf_label = "",
             smf_label = "",
             upf_label = "",
             ric_label = "",
             amf_service_name = "",
             mmc = "",
             mnc = "",
             sst = "",
             sd = "",
             tac = "",
             protectionScheme = "",
             publicKey = "",
             publicKeyId = "",
             routingIndicator = "",
             enabled = "",
             count = "",
             initialMSISDN = "",
             key = "",
             op = "",
             opType = "",
             type = "",
             apn = "",
             emergency = ""

      def initialize()
      end
    end
    
    class ContainerParameters < CNFInstall::Config::ConfigBase
      getter name = "",
             rolling_update_test_tag = "",
             rolling_downgrade_test_tag = "",
             rolling_version_change_test_tag = "",
             rollback_from_tag = ""
      
      def get_container_tag(tag_name)
        # (kosstennbl) TODO: rework version change test and its configuration to get rid of this method.
        case tag_name
        when "rolling_update"
          rolling_update_test_tag
        when "rolling_downgrade"
          rolling_downgrade_test_tag
        when "rolling_version_change"
          rolling_version_change_test_tag
        when "rollback_from"
          rollback_from_tag
        else
          raise ArgumentError.new("Incorrect tag name for container configuration: #{tag_name}")
        end
      end
    end

    class HardcodedIPsAllowed < CNFInstall::Config::ConfigBase
      getter ip : String
    end
  end
end