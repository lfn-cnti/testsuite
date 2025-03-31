require "../spec_helper.cr"

describe "Helm" do
  describe "global" do
    before_all do
      Helm.uninstall_local_helm
    end
    
    it "'Helm.helm_repo_add' should work", tags:["helm"] do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      (stable_repo).should be_true
    end

    it "'Helm.helm_gives_k8s_warning?' should pass when k8s config = chmod 700", tags:["helm"] do
      (Helm.helm_gives_k8s_warning?).should eq({false, nil})
    end

    it "'Helm.global_helm?' should return the information about the helm installation", tags:["helm"] do
      (Helm.global_helm?).should be_true
    end

    it "'Helm::Binary.get?' should find installation", tags:["helm"] do
      Log.info { Helm::Binary.get }
      Helm::Binary.get == "helm"
    end
  end

  describe "local" do
    before_all do
      Helm.install_local_helm
    end

    it "'Helm.helm_repo_add' should work", tags:["helm"] do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      (stable_repo).should be_true
    end

    it "'Helm.helm_gives_k8s_warning?' should pass when k8s config = chmod 700", tags:["helm"] do
      (Helm.helm_gives_k8s_warning?).should eq({false, nil})
    end

    it "'Helm::Binary.get?' should find installation", tags:["helm"] do
      Helm::Binary.get == Setup::HELM_BINARY
    end
  end
end
