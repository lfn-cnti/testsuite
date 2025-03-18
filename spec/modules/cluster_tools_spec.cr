require "../spec_helper"

describe "ClusterTools" do
  before_all do
    begin
      KubectlClient::Apply.namespace(ClusterTools.namespace)
      Log.info { "#{ClusterTools.namespace} namespace created" }
    rescue e : KubectlClient::ShellCMD::AlreadyExistsError
      Log.info { "#{ClusterTools.namespace} namespace already exists on the Kubernetes cluster" }
    end
  end

  after_all do
    ClusterTools.uninstall
  end

  it "ensure_namespace_exists!", tags: ["cluster_tools"] do
    (ClusterTools.ensure_namespace_exists!).should be_true

    KubectlClient::Delete.resource("namespace", "#{ClusterTools.namespace}")

    expect_raises(ClusterTools::NamespaceDoesNotExistException, "ClusterTools Namespace #{ClusterTools.namespace} does not exist") do
      ClusterTools.ensure_namespace_exists!
    end
  end

  it "install", tags: ["cluster_tools"] do
    KubectlClient::Apply.namespace(ClusterTools.namespace)

    (ClusterTools.install).should be_true

    (ClusterTools.ensure_namespace_exists!).should be_true
  end

  it "ensure_namespace_exists! (post install)", tags: ["cluster_tools"] do
    ClusterTools.install
    (ClusterTools.ensure_namespace_exists!).should be_true
  end

  it "pod_name", tags: ["cluster_tools"] do
    (/cluster-tools/ =~ ClusterTools.pod_name).should_not be_nil
  end
end
