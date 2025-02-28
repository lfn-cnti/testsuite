module Dockerd
  def self.install(insecure_registries : Array(String) = [] of String)
    # These are default values to help speed up the cluster setup for the CNF
    insecure_registries_default = ["registry:5000", "registry.default.svc.cluster.local:5000"]
    if insecure_registries.empty?
      insecure_registries = insecure_registries_default
    end

    # If configmaps/docker-config is not present, create one using the default template.
    begin
      docker_config_check = KubectlClient::Get.resource("configmap", "docker-config", TESTSUITE_NAMESPACE)
    rescue KubectlClient::ShellCMD::NotFoundError
      Log.info { "Install dockerd from manifest" }
      KubectlClient::Apply.file(docker_config_manifest_file(insecure_registries), namespace: TESTSUITE_NAMESPACE)
    else
      Log.info { "Skipping docker-config. ConfigMap exists." }
    end

    Log.info { "Install dockerd from manifest" }
    KubectlClient::Apply.file(dockerd_manifest_file, namespace: TESTSUITE_NAMESPACE)
    wait_for_install
  end

  def self.wait_for_install
    Log.info { "Wait for dockerd install" }
    KubectlClient::Wait.resource_wait_for_install("Pod", "dockerd", wait_count: 180, namespace: TESTSUITE_NAMESPACE)
  end

  def self.uninstall
    Log.info { "Uninstall dockerd from manifest" }
    begin
      KubectlClient::Delete.file(dockerd_manifest_file, namespace: TESTSUITE_NAMESPACE)
    rescue KubectlClient::ShellCMD::NotFoundError
    end

    Log.info { "Uninstall docker-config from manifest" }
    begin
      KubectlClient::Delete.resource("configmaps", "docker-config", TESTSUITE_NAMESPACE)
    rescue KubectlClient::ShellCMD::NotFoundError
    end
  end

  def self.exec(cli)
    KubectlClient::Utils.exec("dockerd", cli, namespace: TESTSUITE_NAMESPACE)
  end

  def self.dockerd_manifest_file
    manifest_path = "#{tools_path}/dockerd-manifest.yml"
    unless File.exists?(manifest_path)
      template = DockerdManifest.new.to_s
      File.write(manifest_path, template)
    end
    manifest_path
  end

  # Ignore existing file and overwrite everytime to ensure latest config is present
  def self.docker_config_manifest_file(insecure_registries : Array(String) = [] of String)
    insecure_registries_str = insecure_registries.map {|i| "\"#{i}\""}.join(",")
    manifest_path = "#{tools_path}/docker-config-manifest.yml"
    template = DockerConfigManifest.new(insecure_registries_str).to_s
    File.write(manifest_path, template)
    manifest_path
  end

  class DockerdManifest
    def initialize()
    end
    ECR.def_to_s("src/templates/dockerd-manifest.yml.ecr")
  end

  class DockerConfigManifest
    # The argument for insecure_registries is a string
    # because the template only writes the content
    # and expects a list of comma separated strings.
    def initialize(@insecure_registries : String)
    end
    ECR.def_to_s("src/templates/docker-config.yml.ecr")
  end

end
