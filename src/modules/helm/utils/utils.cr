require "totem"
require "colorize"
require "log"
require "file_utils"
require "../constants.cr"
require "tar"

def stdout_info(msg)
  puts msg
end

def stdout_success(msg)
  puts msg.colorize(:green)
end

def stdout_warning(msg)
  puts msg.colorize(:yellow)
end

def stdout_failure(msg)
  puts msg.colorize(:red)
end

def local_helm_path
  if File.exists?(Helm::BASE_CONFIG)
    config = Totem.from_file Helm::BASE_CONFIG
    if config[":helm_binary_path"]? && config[":helm_binary_path"].as_s?
      return config[":helm_binary_path"].as_s
    end
  end

  Helm::DEFAULT_LOCAL_BINARY_PATH
end

def binary_directory
  "#{local_helm_path}/#{Helm::DEFAULT_ARCH}"
end

def binary_path
  binary_path = "#{binary_directory}/helm"
end

def local_helm_full_path
  return ENV["CUSTOM_HELM_PATH"] if ENV["CUSTOM_HELM_PATH"]?
  "#{FileUtils.pwd}/#{binary_path}"
end

def install_local_helm
  current_dir = FileUtils.pwd
  Log.for("verbose").debug { current_dir }

  FileUtils.mkdir_p(local_helm_path)

  unless File.exists?(binary_path)
    begin
      Log.for("verbose").debug { "pwd? : #{current_dir}" }
      Log.for("verbose").debug { "local_helm_path : #{local_helm_path}" }
      Log.for("verbose").debug { "full path?: #{local_helm_full_path}" }

      stdout = IO::Memory.new
      status = Process.run("wget -P #{binary_directory} https://get.helm.sh/helm-v3.8.2-#{Helm::DEFAULT_ARCH}.tar.gz",
        shell: true, output: stdout, error: stdout
      )

      unless status.success?
        Log.for("verbose").debug { stdout }
        raise "helm download failed"
      end

      TarClient.untar(
        "#{binary_directory}/helm-v3.8.2-#{Helm::DEFAULT_ARCH}.tar.gz",
        "#{local_helm_path}"
      )

      helm = Helm::BinarySingleton.local_helm

      status = Process.run("#{helm} version", shell: true, output: stdout, error: stdout)

      Log.for("verbose").debug { stdout }

      status.success?
    end
  end
end

def helm_local_cleanup
  current_dir = FileUtils.pwd
  path = "#{current_dir}/#{local_helm_path}"
  Log.for("verbose").info { "helm_local_cleanup path: #{path}" }
  FileUtils.rm_rf(path)
end
