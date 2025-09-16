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
             hardcoded_ip_exceptions = [] of HardcodedIPsAllowed,
             tls_profiles = {} of String => TLSConfig,
             auth_defaults = AuthDefaults.new
      def initialize; end
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
             namespace = "",
             tls_profile = "",
             skip_tls_verify = false
    end

    class HelmChartConfig < HelmDeploymentConfig
      # Classic repo fields
      getter helm_repo_name = "",
             helm_chart_name = "",
             helm_repo_url = "",

             # OCI field
             registry_url = "", # oci://host/org/chart
             plain_http = false, 

             # Common
             chart_version = "", # required for OCI; optional for classic
             pass_credentials = false, # forward creds across redirects
             auth : AuthCredentials? = nil  # optional per-chart override

      def after_initialize
        is_oci     = !@registry_url.empty?
        is_classic = !@helm_chart_name.empty? || !@helm_repo_name.empty? || !@helm_repo_url.empty?

        if is_oci && is_classic
          raise YAML::Error.new("Chart \"#{name}\": specify either OCI (registry_url) OR classic (helm_repo_* + helm_chart_name), not both")
        elsif !is_oci && !is_classic
          raise YAML::Error.new("Chart \"#{name}\": missing source. Provide registry_url for OCI or helm_repo_url/name + helm_chart_name for classic")
        end

        if is_oci
          unless @registry_url.starts_with?("oci://")
            raise YAML::Error.new("Chart \"#{name}\": registry_url must start with \"oci://\"")
          end
          if @chart_version.empty?
            raise YAML::Error.new("Chart \"#{name}\": chart_version is required for OCI charts")
          end

          derived = @registry_url.sub(/^oci:\/\//, "").split("/").last
          if !@helm_chart_name.empty?
            Log.warn { "Chart \"#{name}\": helm_chart_name is ignored for OCI charts; using \"#{derived}\" derived from registry_url." }
          end
          @helm_chart_name = derived
        else # classic
          if @helm_chart_name.empty?
            raise YAML::Error.new("Chart \"#{name}\": helm_chart_name is required for classic repos")
          end
          if !@helm_repo_url.empty? && @helm_repo_name.empty?
            raise YAML::Error.new(
              "Chart \"#{name}\": helm_repo_url is set but helm_repo_name is empty. " \
              "Provide an alias in helm_repo_name so the repository can be added."
            )
          end
        end
      end
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

      def initialize; end
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

    class TLSConfig < CNFInstall::Config::ConfigBase
      getter ca_file = "",
             cert_file = "",
             key_file = ""
      def initialize; end
    end

    class AuthDefaults < CNFInstall::Config::ConfigBase
      getter oci_registries = {} of String => AuthCredentials,
             helm_repos     = {} of String => AuthCredentials
      def initialize; end
    end
      
    class AuthCredentials < CNFInstall::Config::ConfigBase
      getter token = "",
             username = "",
             password = ""
      def initialize; end
    end
  end
end