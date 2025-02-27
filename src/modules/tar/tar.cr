require "colorize"
require "log"

# todo put in a separate library. it shold go under ./tools for now
module TarClient
  TAR_REPOSITORY_DIR = "/tmp/repositories"
  TAR_MANIFEST_DIR = "/tmp/manifests"
  TAR_DOWNLOAD_DIR = "/tmp/download"
  TAR_IMAGES_DIR = "/tmp/images"
  TAR_BIN_DIR = "/tmp/bin"
  TAR_TMP_BASE = "/tmp"
  TAR_MODIFY_DIR = "/tmp/modify_tar"

  module ShellCmd
    def self.run(cmd, log_prefix, log_type="debug")
      Log.info { "#{log_prefix} command: #{cmd}" }
      status = Process.run(
        cmd,
        shell: true,
        output: output = IO::Memory.new,
        error: stderr = IO::Memory.new
      )
      if log_type == "debug"
        Log.debug { "#{log_prefix} output: #{output.to_s}" }
        Log.debug { "#{log_prefix} stderr: #{stderr.to_s}" }
      else
        Log.info { "#{log_prefix} output: #{output.to_s}" }
        Log.info { "#{log_prefix} stderr: #{stderr.to_s}" }
      end
      {status: status, output: output.to_s, error: stderr.to_s}
    end
  end

  def self.tar(tarball_name, working_directory, source_file_or_directory, options="")
    Log.info { "cding into #{working_directory} and tarring #{source_file_or_directory} into #{tarball_name}" }
    Log.info { "#{tarball_name} exists?: #{File.exists?(tarball_name)}" }
    if File.exists?(tarball_name)
      ShellCmd.run("tar -tvf #{tarball_name}", "#{tarball_name} contents before", log_type="info")
    end

    cmd = "tar #{options} -czvf #{tarball_name} -C #{working_directory} #{source_file_or_directory}"
    Log.info { "TarClient.tar command: #{cmd}" }
    result = ShellCmd.run(cmd, "TarClient.tar", log_type="info")

    ShellCmd.run("tar -tvf #{tarball_name}", "#{tarball_name} contents after", log_type="info")
    result
  end

  def self.append(tarball_name, working_directory, source_file_or_directory, options="")
    #working_directory: directory to cd into before running the tar command
    Log.info { "cding into #{working_directory} and tarring #{source_file_or_directory} into #{tarball_name}" }
    Log.info { "#{tarball_name} exists?: #{File.exists?(tarball_name)}" }
    if File.exists?(tarball_name)
      Log.info { "#{tarball_name} contents (before tar): #{`tar -tvf #{tarball_name}`}" }
    end

    cmd = "tar #{options} -rf #{tarball_name} -C #{working_directory} #{source_file_or_directory}"
    Log.info { "TarClient.tar (append) command: #{cmd}" }
    status = Process.run(cmd,
                         shell: true,
                         output: output = IO::Memory.new,
                         error: stderr = IO::Memory.new)
    Log.info { "TarClient.tar output: #{output.to_s}" }
    Log.info { "TarClient.tar stderr: #{stderr.to_s}" }
    Log.info { "#{tarball_name} contents (after tar): #{`tar -tvf #{tarball_name}`}" }
    {status: status, output: output, error: stderr}
  end

  def self.untar(tarball_name, destination_directory, options="")
    cmd = "tar #{options} -xvf #{tarball_name} -C #{destination_directory}"
    Log.info { "TarClient.untar command: #{cmd}" }
    status = Process.run(cmd,
                         shell: true,
                         output: output = IO::Memory.new,
                         error: stderr = IO::Memory.new)
    Log.info { "TarClient.untar output: #{output.to_s}" }
    Log.info { "TarClient.untar stderr: #{stderr.to_s}" }
    {status: status, output: output, error: stderr}
  end

  #
  # modify_tar! << untars file, yields to block, retars, keep in tar module
  #
  def self.modify_tar!(tar_file)
    raise "Critical Error" if tar_file.empty? || tar_file == '/'
    tar_name = tar_file.split("/")[-1]
    FileUtils.mkdir_p(TAR_MODIFY_DIR)
    TarClient.untar(tar_file, TAR_MODIFY_DIR)
    yield TAR_MODIFY_DIR
    FileUtils.rm_rf(tar_file)
    file_list = `ls #{TAR_MODIFY_DIR}`.gsub("\n", " ") 
    TarClient.tar(tar_file, TAR_MODIFY_DIR, file_list)
    FileUtils.rm_rf(TAR_MODIFY_DIR)
  end


  def self.tar_file_by_url(url, append_file : String = "./downloaded.tar.gz", output_file="")
    download_path = "download/" 
    FileUtils.rm_rf("/tmp/#{download_path}")
    FileUtils.mkdir_p("/tmp/" + download_path)
    if output_file.empty?
      download_name = url.split("/").last
    else
      download_name = output_file
    end
    download_full_path = download_path + download_name
    Log.info { "download_name: #{download_name}" }
    Log.info { "download_full_path: #{download_full_path}" }
    Halite.get("#{url}") do |response| 
       File.open("/tmp/" + download_full_path, "w") do |file| 
         IO.copy(response.body_io, file)
       end
    end
    TarClient.append(append_file, "/tmp", download_full_path)
  ensure
    FileUtils.rm_rf("/tmp/#{download_path}")
  end

end

