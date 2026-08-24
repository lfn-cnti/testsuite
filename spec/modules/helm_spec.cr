require "../spec_helper.cr"

module Helm
  class Binary
    # test-only: reset memoized path so Binary.get re-evaluates
    def self.clear_cache : Nil
      @@helm = ""
    end
  end
end

describe "Helm" do
  describe "missing" do
    it "installs Helm instead of exposing a missing-binary backtrace", tags: ["helm"] do
      path_without_helm = File.tempname("path-without-helm")
      FileUtils.mkdir_p(path_without_helm)
      tar = Process.find_executable("tar") || raise "spec requires tar in PATH"
      gzip = Process.find_executable("gzip") || raise "spec requires gzip in PATH"
      File.symlink(tar, File.join(path_without_helm, "tar"))
      # GNU tar resolves gzip through PATH when extracting the Helm archive.
      File.symlink(gzip, File.join(path_without_helm, "gzip"))
      Helm.uninstall_local_helm

      result = ShellCmd.run_testsuite("setup:install_local_helm", "PATH=#{path_without_helm}")

      result[:status].success?.should be_true
      File.exists?(Setup::HELM_BINARY).should be_true
      result[:output].should_not contain("No Helm binary found")
      Dir.glob(File.join(Setup::HELM_DIR, "helm-*.tar.gz")).should be_empty
    ensure
      FileUtils.rm_rf(path_without_helm.not_nil!)
      Helm.uninstall_local_helm
    end

    it "fails with guidance and exit 1, not a backtrace, when Helm is missing at runtime", tags: ["helm"] do
      # Empty PATH and an empty tools dir: no global helm, no suite-managed
      # helm. install_jaeger reaches Binary.get without the setup guard.
      empty_path = File.tempname("empty-path")
      empty_tools = File.tempname("empty-tools")
      FileUtils.mkdir_p(empty_path)
      FileUtils.mkdir_p(empty_tools)

      result = ShellCmd.run_testsuite("setup:install_jaeger",
        "PATH=#{empty_path} CNF_TESTSUITE_DIR=#{empty_tools}")

      result[:status].exit_code.should eq(1)
      result[:output].should contain("No Helm binary found")
      result[:output].should contain("cnf-testsuite setup")
      result[:output].should_not contain("__crystal_main")
    ensure
      FileUtils.rm_rf(empty_path.not_nil!)
      FileUtils.rm_rf(empty_tools.not_nil!)
    end
  end

  describe "global" do
    before_all do
      Helm.uninstall_local_helm
      Helm::Binary.clear_cache
    end

    it "'Helm.helm_repo_add' should work", tags: ["helm"] do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      stable_repo.should be_true
    end

    it "'Helm.check' should show no warnings/errors for k8s perms", tags: ["helm"] do
      result = Helm.check
      result.errors.empty?.should be_true
      # No specific warning we care about:
      result.warnings.any? { |w| w =~ /Kubernetes configuration file/ }.should be_false
    end

    it "'Helm.check' should verify a global installation", tags: ["helm"] do
      result = Helm.check
      result.global_ok.should be_true
      result.local_ok.should be_false
    end

    it "'Helm::Binary.get' should find installation", tags: ["helm"] do
      Helm::Binary.get.should eq("helm")
    end
  end

  describe "local" do
    before_all do
      Helm.install_local_helm
      Helm::Binary.clear_cache
    end

    after_all do
      Helm.uninstall_local_helm
      Helm::Binary.clear_cache
    end

    it "'Helm.helm_repo_add' should work", tags: ["helm"] do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      stable_repo.should be_true
    end

    it "'Helm.check' should show no warnings/errors for k8s perms", tags: ["helm"] do
      result = Helm.check
      result.errors.empty?.should be_true
      result.warnings.any? { |w| w =~ /Kubernetes configuration file/ }.should be_false
    end

    it "'Helm.check' should verify a local installation", tags: ["helm"] do
      result = Helm.check
      result.local_ok.should be_true
    end

    it "'Helm::Binary.get' should find installation", tags: ["helm"] do
      Helm::Binary.get.should eq(Setup::HELM_BINARY)
    end
  end
end
