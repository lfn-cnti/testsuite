class ApiSnoop
  # cncf/apisnoop has no releases; pin the clone to a known commit.
  APISNOOP_COMMIT = "256fcf371911"

  def initialize()
  end

  def install_path
    install_dir = "#{tools_path}/apisnoop"
  end

  def install
    ToolInstall.ensure("apisnoop", APISNOOP_COMMIT, install_path) do
      FileUtils.rm_rf(install_path)
      GitClient.clone("https://github.com/cncf/apisnoop #{install_path}")
      ShellCmd.run("git -C #{install_path} checkout --quiet #{APISNOOP_COMMIT}", "apisnoop_checkout")[:status].success?
    end

    # Only for cnf-testsuite CI
    copy_to_docker_host(install_path)
  end

  # [ISSUE-41] Workaround to ensure that the apisnoop dir is copied to the Docker host
  #
  # We are starting a kind cluster within a docker container.
  #
  # Below is our structure.
  #   Host machine -> GitHub Runner -> Kind cluster containers
  #
  # Mounting any volumes within the kind cluster's control plane,
  # requires that the volume exist on the host machine.
  #
  # 1. We create /github-runner-cnf-testsuite/cnf-testsuite/cnf-testsuite/tools/apisnoop dir
  #    on the docker host as a part of our GitHub Actions workflow.
  #
  # 2. The above dir is mounted on the docker container as /apisnoop
  #
  # 3. During apisnoop install, if the dir exists, we copy the apisnoop repo to the shared directory
  #    This ensures that it is available on the docker host.
  #
  # When kind looks for the kubernetes manifest file for apisnoop, it'll be available in the expected dir.
  # For details about the bind source & destination, check tools/github-runner/create_runners.sh
  def copy_to_docker_host(install_path)
    shared_tools_dir = "/docker-host-repo/tools"
    if Dir.exists?(shared_tools_dir)
      FileUtils.cp_r(install_path, shared_tools_dir)
      Log.info { "Copied apisnoop to docker host mounted shared dir" }
    end
  end

  def setup_kind_cluster(name : String, k8s_version : String)
    result = ShellCmd.run("docker --version", "apisnoop_docker_version", true)
    Log.info { "Docker version: #{result[:output]}" }
    kind_manager = KindManager.new
    FileUtils.cd("#{install_path}/kind") do
      Log.for("apisnoop_kind_dir").info { FileUtils.pwd }
      ShellCmd.run("pwd", "apisnoop_setup_kind_dir", true)
      kind_config = "kind+apisnoop.yaml"
      cluster = kind_manager.create_cluster(name, kind_config, k8s_version)
      cluster.wait_until_nodes_ready()
      cluster.wait_until_pods_ready()
      return cluster
    end
  end

end
