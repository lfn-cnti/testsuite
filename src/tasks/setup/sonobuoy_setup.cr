require "sam"
require "file_utils"
require "colorize"
require "totem"
require "http/client"
require "halite" 
require "../utils/utils.cr"

def sonobuoy_details(cmd_path : String)
  Log.trace { cmd_path }
  stdout = IO::Memory.new
  status = Process.run("#{cmd_path} version", shell: true, output: stdout, error: stdout)
  Log.debug { stdout }
end

desc "Sets up Sonobuoy in the K8s Cluster"
task "install_sonobuoy" do |_, args|
  #TODO: Fetch version dynamically
  # k8s_version = HTTP::Client.get("https://storage.googleapis.com/kubernetes-release/release/stable.txt").body.chomp.split(".")[0..1].join(".").gsub("v", "") 
  # TODO make k8s_version dynamic
  # TODO use kubectl version and grab the server version
  # k8s_version = "0.19.0"
  Log.trace { SONOBUOY_K8S_VERSION }
  current_dir = FileUtils.pwd 
  Log.trace { current_dir }
  unless Dir.exists?("#{Setup::SONOBUOY_DIR}")
    Log.trace { "toolsdir : #{tools_path}" }
    Log.trace { "full path?: #{Setup::SONOBUOY_DIR}" }
    FileUtils.mkdir_p("#{Setup::SONOBUOY_DIR}")
    url = Setup::SONOBUOY_URL
    write_file = "#{Setup::SONOBUOY_DIR}/sonobuoy.tar.gz"
    Log.info { "url: #{url}" }
    Log.info { "write_file: #{write_file}" }
    # todo change this to work with rel 
    # todo I think http get doesn't do follows and thats why we use halite here, that's sad. Shouldn't need to do a follow to download a file though?
     #  i think any url can do a redirect  ....
    # it could be that http.get 'just works' now.  keyword just
    download_file("#{url}","#{write_file}")
    `tar -xzf #{Setup::SONOBUOY_DIR}/sonobuoy.tar.gz -C #{Setup::SONOBUOY_DIR}/ && \
     chmod +x #{Setup::SONOBUOY_DIR}/sonobuoy && \
     rm #{Setup::SONOBUOY_DIR}/sonobuoy.tar.gz`
    sonobuoy = Setup::SONOBUOY_BINARY
    sonobuoy_details(sonobuoy)
  end
end

desc "Uninstalls Sonobuoy"
task "uninstall_sonobuoy" do |_, args|
  current_dir = FileUtils.pwd 
  sonobuoy = Setup::SONOBUOY_BINARY
  status = Process.run(
    "#{sonobuoy} delete --wait 2>&1",
    shell: true,
    output: stdout = IO::Memory.new,
    error: stderr = IO::Memory.new
  ) if File.exists?(sonobuoy)
  Log.debug { stdout }
  FileUtils.rm_rf("#{Setup::SONOBUOY_DIR}")
end

