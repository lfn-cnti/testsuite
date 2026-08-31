require "sam"
require "file_utils"
require "colorize"
require "totem"
require "http/client"
require "halite"
require "../utils/utils.cr"
require "json"
require "yaml"

namespace "setup" do
  desc "Install Cluster API for Kind"
  task "cluster_api_install" do |_, args|
    # The binary lives with the other tools; no sudo, no /usr/local/bin.
    ToolInstall.ensure("clusterctl", Setup::CLUSTER_API_VERSION, Setup::CLUSTERCTL_BINARY) do
      download_file(Setup::CLUSTER_API_URL, Setup::CLUSTERCTL_BINARY)
      File.chmod(Setup::CLUSTERCTL_BINARY, 0o755)
      Log.info { "Completed downloading clusterctl" }
      true
    end

    clusterctl = Path["~/.cluster-api"].expand(home: true)

    FileUtils.mkdir_p("#{clusterctl}")

    File.write("#{clusterctl}/clusterctl.yaml", "CLUSTER_TOPOLOGY: \"true\"")

    StatusLine.push "Initializing Cluster API management components (several minutes on first run)..."
    cluster_init_cmd = "#{Setup::CLUSTERCTL_BINARY} init --infrastructure docker --wait-providers"
    stdout = IO::Memory.new
    Process.run(cluster_init_cmd, shell: true, output: stdout, error: stdout)
    Log.for("clusterctl init").info { stdout }
    StatusLine.pop

    create_cluster_file = File.join(Setup::CLUSTER_API_DIR, "capi.yaml")

    create_cluster_cmd = "#{Setup::CLUSTERCTL_BINARY} generate cluster capi-quickstart   --kubernetes-version v1.24.0   --control-plane-machine-count=3 --worker-machine-count=3  --flavor development > #{create_cluster_file} "

    Process.run(
      create_cluster_cmd,
      shell: true,
      output: create_cluster_stdout = IO::Memory.new,
      error: create_cluster_stderr = IO::Memory.new
    )

    # TODO (rafal-lal): Connection error is expected in first couple tries, but it's not
    # reasonable to rescue it inside 'wait_for_install_by_apply' method, hence the while
    # loop here. Ideally this should be implemented in different way so we don't have to
    # rescue NetworkError at all. 'loop_count' var added so testsuite won't hang
    # indefinitely here.
    loop_break = false
    loop_count = 0
    while !loop_break && loop_count < 10
      begin
        KubectlClient::Wait.wait_for_install_by_apply(create_cluster_file)
        loop_break = true
      rescue KubectlClient::ShellCMD::NetworkError
        sleep 3.seconds
        loop_count += 1
      end
    end

    Log.for("clusterctl-create").info { create_cluster_stdout.to_s }
    Log.info { "cluster api setup complete" }
  end

  desc "Uninstall Cluster API"
  task "cluster_api_uninstall" do |_, args|
    cmd = "kubectl delete cluster capi-quickstart --wait"
    Process.run(cmd, shell: true, output: stdout = IO::Memory.new, error: stderr = IO::Memory.new)
    Log.debug { "#{cmd}: #{stdout.to_s}" }

    cmd = "#{Setup::CLUSTERCTL_BINARY} delete --all --include-crd --include-namespace"
    Process.run(cmd, shell: true, output: stdout = IO::Memory.new, error: stderr = IO::Memory.new)
    Log.debug { "#{cmd}: #{stdout.to_s}" }
  end
end
