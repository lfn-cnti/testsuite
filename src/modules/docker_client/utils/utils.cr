require "totem"
require "colorize"
require "log"
require "file_utils"
require "../constants.cr"

def local_docker_path
  File.join(FileUtils.pwd, DockerClient::DEFAULT_LOCAL_BINARY_PATH)
end