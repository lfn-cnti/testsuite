require "../spec_helper.cr"

describe "Helm" do
  describe "global" do
    before_all do
      helm_local_cleanup
    end

    it "local helm should not be detected", tags:["helm"] do
      (Helm::BinarySingleton.local_helm_installed?).should be_false
    end

    it "'Helm.helm_repo_add' should work", tags:["helm"] do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      (stable_repo).should be_true
    end

    it "'Helm.helm_gives_k8s_warning?' should pass when k8s config = chmod 700", tags:["helm"] do
      (Helm.helm_gives_k8s_warning?).should eq({false, nil})
    end

    it "'helm_installation_info()' should return the information about the helm installation", tags:["helm"] do
      (Helm::SystemInfo.helm_installation_info(true)).should contain("helm found")
    end

    it "'Helm::SystemInfo.global_helm_installed?' should return the information about the helm installation", tags:["helm"] do
      (Helm::SystemInfo.global_helm_installed?).should be_true
    end

    it "local helm should not be detected", tags:["helm"] do
      (Helm::BinarySingleton.local_helm_installed?).should be_false
    end

    it "'Helm::BinarySingleton.installation_found?' should find installation", tags:["helm"] do
      (Helm::BinarySingleton.installation_found?).should be_true
    end

    it "'helm_global_response()' should return the information about the helm installation", tags:["helm"] do
      (helm_global_response(true)).should contain("\"v3.")
    end

    it "'helm_installations()' should return the information about the helm installation", tags:["helm"] do
      (helm_installation(true)).should contain("helm found")
    end
  end

  describe "local" do
    before_all do
      install_local_helm
    end

    it "local helm should be detected", tags:["helm"] do
      (Helm::BinarySingleton.local_helm_installed?).should be_true
    end

    it "'Helm.helm_repo_add' should work", tags:["helm"] do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      (stable_repo).should be_true
    end

    it "'Helm.helm_gives_k8s_warning?' should pass when k8s config = chmod 700", tags:["helm"] do
      (Helm.helm_gives_k8s_warning?).should eq({false, nil})
    end

    it "'helm_installation_info()' should return the information about the helm installation", tags:["helm"] do
      (Helm::SystemInfo.helm_installation_info(true)).should contain("helm found")
    end

    it "'Helm::SystemInfo.local_helm_installed?' should return the information about the helm installation", tags:["helm"] do
      (Helm::SystemInfo.local_helm_installed?).should be_true
    end

    it "'Helm::BinarySingleton.installation_found?' should find installation", tags:["helm"] do
      (Helm::BinarySingleton.installation_found?).should be_true
    end

    it "'helm_local_response()' should return the information about the helm installation", tags:["helm"] do
      Helm::ShellCMD.run("ls -R tools/helm", Helm::Log.for("helm_dir_check"), force_output: true)
      (helm_local_response(true)).should contain("\"v3.")
    end

    it "'helm_version()' should return the information about the helm version", tags:["helm"] do
      Helm::ShellCMD.run("ls -R tools/helm", Helm::Log.for("helm_dir_check"), force_output: true)
      (helm_version(helm_local_response)).should contain("v3.")
    end

    it "local helm should be detected", tags:["helm"] do
      (Helm::BinarySingleton.local_helm_installed?).should be_true
    end
  end
end
