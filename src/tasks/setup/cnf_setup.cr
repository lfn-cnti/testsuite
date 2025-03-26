require "sam"
require "file_utils"
require "colorize"
require "totem"
require "yaml"
require "./utils/utils.cr"

task "generate_config" do |_, args|
  interactively_create_config()
end

task "cnf_install", ["helm_local_install", "create_namespace"] do |_, args|
  if CNFManager.cnf_installed?
    stdout_warning "A CNF is already installed. Installation of multiple CNFs is not allowed."
    stdout_warning "To install a new CNF, uninstall the existing one by running: cnf_uninstall"
    exit 0
  end
  if ClusterTools.install
    stdout_success "ClusterTools installed"
  else
    stdout_failure "The ClusterTools installation timed out. Please check the status of the cluster-tools pods."
    exit 1
  end
  stdout_success "CNF installation start."
  CNFInstall.install_cnf(args)
  stdout_success "CNF installation complete."
end

task "cnf_uninstall" do |_, args|
  CNFInstall.uninstall_cnf()
end

def interactively_create_config
  new_config = {
    config_version: CNFInstall::Config::ConfigVersion::Latest.to_s,
    deployments: {
      helm_charts: [] of Hash(String, String),
      helm_dirs: [] of Hash(String, String),
      manifests: [] of Hash(String, String)
    }
  }

  loop do
    puts "Select deployment type:"
    puts "1. Helm Chart"
    puts "2. Helm Directory"
    puts "3. Manifest Directory"
    puts "4. Finish and save configuration"
    choice = prompt("Enter your choice (1-4): ")

    case choice
    when "1"
      helm_chart = {
        "name" => prompt("Enter deployment name: "),
        "helm_repo_name" => prompt("Enter Helm repository name: "),
        "helm_repo_url" => prompt("Enter Helm repository URL: "),
        "helm_chart_name" => prompt("Enter Helm chart name: ")
      }
      helm_chart["helm_chart_name"] = helm_chart["helm_chart_name"]
      new_config[:deployments][:helm_charts] << helm_chart
    when "2"
      helm_dir = {
        "name" => prompt("Enter deployment name: "),
        "helm_directory" => prompt("Enter path to directory with Chart.yaml: ")
      }
      new_config[:deployments][:helm_dirs] << helm_dir
    when "3"
      manifest = {
        "name" => prompt("Enter deployment name: "),
        "manifest_directory" => prompt("Enter path to directory with manifest files: ")
      }
      new_config[:deployments][:manifests] << manifest
    when "4"
      break
    else
      puts "Invalid choice. Please try again."
    end
  end

  yaml_config = new_config.to_yaml
  puts "Generated Configuration:"
  puts yaml_config

  output_file = prompt("Choose output config path (leave empty for #{CONFIG_FILE}): ")
  if output_file.strip.empty?
    output_file = CONFIG_FILE
  end
  File.write(output_file, yaml_config)
  puts "Configuration saved to #{output_file}"
end

def prompt(message)
  print message
  gets.try(&.strip) || ""
end
