require "../config_versions/config_versions.cr"
require "./deployment_manager_common.cr"

module CNFInstall
  abstract class HelmDeploymentManager < DeploymentManager
    def initialize(deployment_name, deployment_priority)
      super(deployment_name, deployment_priority)
    end

    abstract def get_deployment_config() : ConfigV2::HelmDeploymentConfig

    def get_deployment_name()
      helm_deployment_config = get_deployment_config()
      helm_deployment_config.name()
    end

    def get_deployment_namespace()
      helm_deployment_config = get_deployment_config()
      helm_deployment_config.namespace.empty? ? DEFAULT_CNF_NAMESPACE : helm_deployment_config.namespace
    end

    def install_from_folder(chart_path, helm_namespace, helm_values)
      begin
        CNFManager.ensure_namespace_exists!(helm_namespace)
        response = Helm.install(@deployment_name, chart_path, namespace: helm_namespace, values: helm_values)
        # Save the stderr from installation command for usage in other tests.
        unless response[:output].empty?
          File.open(CNF_INSTALL_LOG_FILE, "a") { |file| file.puts("#{response[:error]}\n") }
        end
      rescue e : Helm::ShellCMD::CannotReuseReleaseNameError
        stdout_failure "Helm deployment \"#{@deployment_name}\" already exists in \"#{helm_namespace}\" namespace."
        stdout_failure "Change deployment name in CNF configuration or uninstall existing deployment."
        return false
      rescue e : Helm::ShellCMD::HelmCMDException
        stdout_failure "Helm installation failed with message:"
        stdout_failure "\t#{e.message}"
        return false
      end

      true
    end

    def uninstall()
      begin
        result = Helm.uninstall(get_deployment_name(), get_deployment_namespace(), wait: false)
      rescue ex : Helm::ShellCMD::ReleaseNotFound
        stdout_warning "Helm deployment \"#{deployment_name}\" was not installed."
        true
      rescue ex : Helm::ShellCMD::HelmCMDException
        stdout_failure "Error while uninstalling helm deployment \"#{deployment_name}\":"
        stdout_failure "\t#{ex.message}"
        false
      end

      true
    end

    def generate_manifest()
      namespace = get_deployment_namespace()
      generated_manifest = Helm.generate_manifest(get_deployment_name(), namespace)
      generated_manifest_with_namespaces = Manifest.add_namespace_to_resources(generated_manifest, namespace)
    end
  end

  class HelmChartDeploymentManager < HelmDeploymentManager
    @helm_chart_config : ConfigV2::HelmChartConfig
    @common : ConfigV2::CommonParameters
    
    def initialize(helm_chart_config : ConfigV2::HelmChartConfig, @common : ConfigV2::CommonParameters)
      super(helm_chart_config.name, helm_chart_config.priority)
      @helm_chart_config = helm_chart_config
      @common = common
    end

    def install()
      skip_tls_verify = @helm_chart_config.skip_tls_verify

      ca_file   : String? = nil
      cert_file : String? = nil
      key_file  : String? = nil

      if tls = resolve_tls(@helm_chart_config.tls_profile)
        ca_file   = tls.ca_file.empty?   ? nil : tls.ca_file
        cert_file = tls.cert_file.empty? ? nil : tls.cert_file
        key_file  = tls.key_file.empty?  ? nil : tls.key_file
      end

      pull_destination = File.join(DEPLOYMENTS_DIR, @deployment_name)

      ok = 
        if !@helm_chart_config.registry_url.empty?
          prepare_oci_install(pull_destination, ca_file, cert_file, key_file, skip_tls_verify)
        else
          prepare_classic_install(pull_destination, ca_file, cert_file, key_file, skip_tls_verify)
        end
      
      return false unless ok
      
      chart_path = File.join(pull_destination, @helm_chart_config.helm_chart_name)
      install_from_folder(chart_path, get_deployment_namespace(), @helm_chart_config.helm_values)
    end

    def get_deployment_config() : ConfigV2::HelmDeploymentConfig
      @helm_chart_config
    end

    private def prepare_oci_install(
      pull_destination : String,
      ca_file : String?,
      cert_file : String?,
      key_file : String?,
      skip_tls_verify : Bool
    ) : Bool
      registry_host      = oci_host(@helm_chart_config.registry_url)
      username, password = resolve_credentials(
        @helm_chart_config.auth,
        @common.auth_defaults.oci_registries[registry_host]?
      )

      Helm.registry_login(
        registry_host,
        username: username, password: password,
        ca_file: ca_file, cert_file: cert_file, key_file: key_file,
        insecure: skip_tls_verify
      )

      begin
        Helm.pull_oci(
          @helm_chart_config.registry_url,
          version: @helm_chart_config.chart_version,
          destination: pull_destination,
          untar: true,
          ca_file: ca_file, cert_file: cert_file, key_file: key_file,
          insecure_skip_tls_verify: skip_tls_verify,
          plain_http: @helm_chart_config.plain_http
        )
      rescue ex : Helm::ShellCMD::HelmCMDException
        stdout_failure "Helm OCI pull failed for deployment \"#{get_deployment_name()}\": #{ex.message}"
        return false
      end

      true
    end

    private def prepare_classic_install(
      pull_destination : String,
      ca_file : String?,
      cert_file : String?,
      key_file : String?,
      skip_tls_verify : Bool
    ) : Bool
      repo_name  = @helm_chart_config.helm_repo_name
      repo_url   = @helm_chart_config.helm_repo_url
      chart_name = @helm_chart_config.helm_chart_name

      username, password = resolve_credentials(
        @helm_chart_config.auth,
        @common.auth_defaults.helm_repos[repo_name]?
      )

      unless repo_url.empty?
        Helm.helm_repo_add(
          repo_name, repo_url,
          username: username, password: password,
          ca_file: ca_file, cert_file: cert_file, key_file: key_file,
          insecure_skip_tls_verify: skip_tls_verify,
          pass_credentials: @helm_chart_config.pass_credentials
        )
      end

      begin
        Helm.pull(
          repo_name, chart_name,
          version: @helm_chart_config.chart_version.empty? ? nil : @helm_chart_config.chart_version,
          destination: pull_destination,
          untar: true
        )
      rescue ex : Helm::ShellCMD::HelmCMDException
        stdout_failure "Helm pull failed for deployment \"#{get_deployment_name()}\": #{ex.message}"
        return false
      end

      true
    end

    private def oci_host(oci_url : String) : String
      stripped = oci_url.sub(/^oci:\/\//, "")
      stripped.split('/').first
    end

    private def resolve_tls(profile_name : String) : ConfigV2::TLSConfig?
      return nil if profile_name.empty?
      @common.tls_profiles[profile_name]?
    end

    # Returns {username, password} (may be empty strings if not provided).
    private def resolve_credentials(override : ConfigV2::AuthCredentials?, defaults : ConfigV2::AuthCredentials?) : {String, String}
      if override
        username = override.username
        password = !override.token.empty? ? override.token : override.password
        return {username, password}
      end

      if defaults
        username = defaults.username
        password = !defaults.token.empty? ? defaults.token : defaults.password
        return {username, password}
      end

      {"", ""}
    end
  end

  class HelmDirectoryDeploymentManager < HelmDeploymentManager
    @helm_directory_config : ConfigV2::HelmDirectoryConfig

    def initialize(helm_directory_config)
      super(helm_directory_config.name, helm_directory_config.priority)
      @helm_directory_config = helm_directory_config
    end

    def install()
      chart_path = File.join(DEPLOYMENTS_DIR, @deployment_name, File.basename(@helm_directory_config.helm_directory))
      install_from_folder(chart_path, get_deployment_namespace(), @helm_directory_config.helm_values)
    end

    def get_deployment_config() : ConfigV2::HelmDeploymentConfig
      @helm_directory_config
    end
  end
end