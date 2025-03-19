require "totem"
require "colorize"
require "log"
require "file_utils"
require "../constants.cr"

def local_docker_path
  if File.exists?(DockerClient::BASE_CONFIG)
    config = Totem.from_file DockerClient::BASE_CONFIG
    if config[":docker_binary_path"]? && config[":docker_binary_path"].as_s?
      return config[":docker_binary_path"].as_s
    end
  end

  FileUtils.pwd + DockerClient::DEFAULT_LOCAL_BINARY_PATH
end