require "../spec_helper.cr"
require "file_utils"

TAR_SPEC_DIR="./tar_spec_dir"

def self.find(directory, wildcard="*.tar*", maxdepth="1", silent=true)
  Log.info { "find command: find #{directory} -maxdepth #{maxdepth} -name #{wildcard}" }
  status = Process.run("find #{directory} -maxdepth #{maxdepth} -name \"#{wildcard}\"",
                       shell: true,
                       output: output = IO::Memory.new,
                       error: stderr = IO::Memory.new)
  found_files = output.to_s.split("\n").select{|x| x.empty? == false}
  if found_files.size == 0 && !silent
    raise "No files found!"
  end
  found_files
end

describe "TarClient" do
  before_all do
    Dir.mkdir(TAR_SPEC_DIR)
  end

  after_all do
    Dir.delete(TAR_SPEC_DIR)
  end

  it "'.tar' should tar a source file or directory", tags:["tar"]  do
    `rm #{TAR_SPEC_DIR}/test.tar`
    TarClient.tar("#{TAR_SPEC_DIR}/test.tar", "./spec/fixtures", "cnf-testsuite.yml")
    (File.exists?("./spec/fixtures/cnf-testsuite.yml")).should be_true
  ensure
    `rm #{TAR_SPEC_DIR}/test.tar`
  end

  it "'.untar' should untar a tar file into a directory", tags:["tar"]  do
    `rm #{TAR_SPEC_DIR}/test.tar`
    TarClient.tar("#{TAR_SPEC_DIR}/test.tar", "./spec/fixtures", "cnf-testsuite.yml")
    TarClient.untar("#{TAR_SPEC_DIR}/test.tar", "#{TAR_SPEC_DIR}")
    (File.exists?("#{TAR_SPEC_DIR}/cnf-testsuite.yml")).should be_true
  ensure
    `rm #{TAR_SPEC_DIR}/test.tar`
    `rm #{TAR_SPEC_DIR}/cnf-testsuite.yml`
  end

  it "'.modify_tar!' should untar file, yield to block, retar", tags:["tar"]  do
    `rm #{TAR_SPEC_DIR}/test.tar`
    input_content = File.read("./spec/fixtures/litmus-operator-v1.13.2.yaml") 
    (input_content =~ /imagePullPolicy: Never/).should be_nil
    TarClient.tar("#{TAR_SPEC_DIR}/test.tar", "./spec/fixtures", "litmus-operator-v1.13.2.yaml")
    TarClient.modify_tar!("#{TAR_SPEC_DIR}/test.tar") do |directory| 
      template_files = Find.find(directory, "*.yaml*", "100")
      Log.debug {"template_files: #{template_files}"}
      template_files.map do |x| 
        input_content = File.read(x) 
        output_content = input_content.gsub(/(.*imagePullPolicy:)(.*)/,"\\1 Never")

        input_content = File.write(x, output_content) 
      end
    end

    TarClient.untar("#{TAR_SPEC_DIR}/test.tar", "#{TAR_SPEC_DIR}")
    (File.exists?("#{TAR_SPEC_DIR}/litmus-operator-v1.13.2.yaml")).should be_true
    input_content = File.read("#{TAR_SPEC_DIR}/litmus-operator-v1.13.2.yaml") 
    (input_content =~ /imagePullPolicy: Never/).should_not be_nil
  ensure
    `rm #{TAR_SPEC_DIR}/test.tar`
    `rm #{TAR_SPEC_DIR}/litmus-operator-v1.13.2.yaml`
  end

end
