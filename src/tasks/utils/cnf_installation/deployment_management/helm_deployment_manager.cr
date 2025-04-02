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
        result = Helm.uninstall(get_deployment_name(), get_deployment_namespace())
      rescue ex : Helm::ShellCMD::ReleaseNotFound
        stdout_success "Helm deployment not installed \"#{deployment_name}\"."
        true
      rescue ex : Helm::ShellCMD::HelmCMDException
        stdout_failure "Error while uninstalling helm deployment \"#{deployment_name}\"."
        stdout_failure "\t#{ex.message}"
        false
      else
        stdout_success "Successfully uninstalled helm deployment \"#{deployment_name}\"."
        true
      end
    end

    def generate_manifest()
      namespace = get_deployment_namespace()
      generated_manifest = Helm.generate_manifest(get_deployment_name(), namespace)
      generated_manifest_with_namespaces = Manifest.add_namespace_to_resources(generated_manifest, namespace)
    end
  end

  class HelmChartDeploymentManager < HelmDeploymentManager
    @helm_chart_config : ConfigV2::HelmChartConfig
    
    def initialize(helm_chart_config)
      super(helm_chart_config.name, helm_chart_config.priority)
      @helm_chart_config = helm_chart_config
    end

    def install()
      helm_repo_url = @helm_chart_config.helm_repo_url
      helm_repo_name = @helm_chart_config.helm_repo_name
      helm_chart_name = @helm_chart_config.helm_chart_name

      if !helm_repo_url.empty?
        Helm.helm_repo_add(helm_repo_name, helm_repo_url)
      end
      helm_pull_destination = File.join(DEPLOYMENTS_DIR, @deployment_name)
      begin
        Helm.pull(helm_repo_name, helm_chart_name, destination: helm_pull_destination)
      rescue ex : Helm::ShellCMD::RepoNotFound
        stdout_failure "Helm pull failed for deployment \"#{get_deployment_name()}\": #{ex.message}"
        return false
      end

      chart_path = File.join(helm_pull_destination, helm_chart_name)
      install_from_folder(chart_path, get_deployment_namespace(), @helm_chart_config.helm_values)
      true
    end

    def get_deployment_config() : ConfigV2::HelmDeploymentConfig
      @helm_chart_config
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