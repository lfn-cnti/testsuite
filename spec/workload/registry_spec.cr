require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "kubectl_client"
require "helm"
require "../../src/tasks/dockerd_setup.cr"
require "file_utils"
require "sam"

def registry_manifest_path
  Path[__DIR__].parent.parent / "tools/registry/manifest.yml"
end

describe "Private Registry: Image" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    Dockerd.install
    install_registry = KubectlClient::Apply.file(registry_manifest_path.to_s)
    KubectlClient::Wait.resource_wait_for_install("Pod", "registry")

    Dockerd.exec("apk add curl")
    Dockerd.exec("curl http://example.com")

    if ENV["DOCKERHUB_USERNAME"]? && ENV["DOCKERHUB_PASSWORD"]?
      result = Dockerd.exec("docker login -u $DOCKERHUB_USERNAME -p $DOCKERHUB_PASSWORD",)
      Log.info { "Docker Login output: #{result[:output]}" }
    end

    private_registry = "registry.default.svc.cluster.local:5000"
    Dockerd.exec("docker pull coredns/coredns:1.6.7")
    Dockerd.exec("docker tag coredns/coredns:1.6.7 #{private_registry}/coredns:1.6.7",)
    Dockerd.exec("docker push #{private_registry}/coredns:1.6.7")

    # This is required for the test that uses the sample_local_registry_org_image CNF
    Dockerd.exec("docker tag coredns/coredns:1.6.7 #{private_registry}/coredns-sample-org/coredns:1.6.7")
    Dockerd.exec("docker push #{private_registry}/coredns-sample-org/coredns:1.6.7")
  end

  it "'reasonable_image_size' should pass if using local registry and a port", tags: ["private_registry_image"]  do
    cnf="./sample-cnfs/sample_local_registry"

    ShellCmd.cnf_install("cnf-path=#{cnf}")
    result = ShellCmd.run_testsuite("reasonable_image_size")
    result[:status].success?.should be_true
    (/Image size is good/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  it "'reasonable_image_size' should pass if using local registry, a port and an org", tags: ["private_registry_image"]  do
    cnf="./sample-cnfs/sample_local_registry_org_image"

    ShellCmd.cnf_install("cnf-path=#{cnf}")
    result = ShellCmd.run_testsuite("reasonable_image_size")
    result[:status].success?.should be_true
    (/Image size is good/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
  end

  after_all do
    # TODO (rafal-lal): Why manifest file has 'default' namespace defined in it?
    # We wouldn't need to catch this exception otherwise.
    begin
      delete_registry = KubectlClient::Delete.file(registry_manifest_path.to_s)
    rescue ex : KubectlClient::ShellCMD::UnspecifiedError
      unless /this namespace may not be deleted/i.match("#{ex.message}")
        raise ex
      end
    end
    Dockerd.uninstall
  end	
end

describe "Private Registry: Rolling" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    Dockerd.install
    install_registry = KubectlClient::Apply.file(registry_manifest_path.to_s)
    KubectlClient::Wait.resource_wait_for_install("Pod", "registry")

    Dockerd.exec("apk add curl")
    Dockerd.exec("curl http://example.com")

    private_registry = "registry.default.svc.cluster.local:5000"
    Dockerd.exec("docker pull coredns/coredns:1.6.7")
    Dockerd.exec("docker tag coredns/coredns:1.6.7 #{private_registry}/coredns:1.6.7")
    Dockerd.exec("docker push #{private_registry}/coredns:1.6.7")

    Dockerd.exec("docker pull coredns/coredns:1.8.0")
    Dockerd.exec("docker tag coredns/coredns:1.8.0 #{private_registry}/coredns:1.8.0")
    Dockerd.exec("docker push #{private_registry}/coredns:1.8.0")
  end

  it "'rolling_update' should pass if using local registry and a port", tags: ["private_registry_rolling"]  do
    begin
      cnf="./sample-cnfs/sample_local_registry_rolling"

      ShellCmd.cnf_install("cnf-path=#{cnf}")
      result = ShellCmd.run_testsuite("rolling_update")
      result[:status].success?.should be_true
      (/Passed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall("timeout=0")
    end
  end

  it "'rolling_downgrade' should pass if using local registry and a port", tags: ["private_registry_rolling"]  do
    begin
      cnf="./sample-cnfs/sample_local_registry_rolling"

      ShellCmd.cnf_install("cnf-path=#{cnf}")
      result = ShellCmd.run_testsuite("rolling_update")
      result[:status].success?.should be_true
      (/Passed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall("timeout=0")
  	end
  end

  it "'rolling_version_change' should pass if using local registry and a port", tags: ["private_registry_version"]  do
    begin
      cnf="./sample-cnfs/sample_local_registry_rolling"

      ShellCmd.cnf_install("cnf-path=#{cnf}")
      result = ShellCmd.run_testsuite("rolling_version_change")
      result[:status].success?.should be_true
      (/Passed/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall("timeout=0")
    end
  end  

  after_all do
    delete_registry = KubectlClient::Delete.file(registry_manifest_path.to_s)
    Dockerd.uninstall
  end	
end
