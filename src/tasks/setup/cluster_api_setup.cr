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
    current_dir = FileUtils.pwd

    download(Setup::CLUSTER_API_URL, Setup::CLUSTERCTL_BINARY)

    Process.run(
      "sudo chmod +x ./clusterctl",
      shell: true,
      output: stdout = IO::Memory.new,
      error: stderr = IO::Memory.new
    )
    Process.run(
      "sudo mv ./clusterctl /usr/local/bin/clusterctl",
      shell: true,
      output: stdout = IO::Memory.new,
      error: stderr = IO::Memory.new
    )

    Log.info { "Completed downloading clusterctl" }

    clusterctl = Path["~/.cluster-api"].expand(home: true)

    FileUtils.mkdir_p("#{clusterctl}")

    File.write("#{clusterctl}/clusterctl.yaml", "CLUSTER_TOPOLOGY: \"true\"")

    cluster_init_cmd = "clusterctl init --infrastructure docker"
    stdout = IO::Memory.new
    Process.run(cluster_init_cmd, shell: true, output: stdout, error: stdout)
    Log.for("clusterctl init").info { stdout }

    create_cluster_file = "#{current_dir}/capi.yaml"

    create_cluster_cmd = "clusterctl generate cluster capi-quickstart   --kubernetes-version v1.24.0   --control-plane-machine-count=3 --worker-machine-count=3  --flavor development > #{create_cluster_file} "

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
    current_dir = FileUtils.pwd
    delete_cluster_file = "#{current_dir}/capi.yaml"
    begin KubectlClient::Delete.file("#{delete_cluster_file}") rescue KubectlClient::ShellCMD::NotFoundError end

    cmd = "clusterctl delete --all --include-crd --include-namespace"
    Process.run(cmd, shell: true, output: stdout = IO::Memory.new, error: stderr = IO::Memory.new)
  end
end
