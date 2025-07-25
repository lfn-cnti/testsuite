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