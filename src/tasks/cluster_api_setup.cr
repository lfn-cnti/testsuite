require "sam"
require "file_utils"
require "colorize"
require "totem"
require "http/client"
require "halite"
require "./utils/utils.cr"
require "json"
require "yaml"

desc "Install Cluster API for Kind"
task "cluster_api_install" do |_, args|
  current_dir = FileUtils.pwd

  HttpHelper.download("https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.2.0/clusterctl-linux-amd64", "clusterctl")

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

  KubectlClient::Wait.wait_for_install_by_apply(create_cluster_file)

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
