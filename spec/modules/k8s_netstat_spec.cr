require "../spec_helper"

describe "netstat" do
  before_all do
    begin
      KubectlClient::Apply.namespace("cnf-testsuite")
    rescue e : KubectlClient::ShellCMD::AlreadyExistsError
    end
    ClusterTools.install
  end

  after_all do
    # Cleanup logic after all tests have run
    begin
      KubectlClient::Delete.resource("pvc", "data-wordpress-mariadb-0")
      KubectlClient::Delete.resource("pvc", "wordpress")
    rescue ex : KubectlClient::ShellCMD::NotFoundError
    end
    Log.info { "Cleanup complete" }
  end

  it "cnf with two services on the cluster that connect to the same database", tags: ["k8s_netstat"] do
    release_name = "wordpress"
    helm_chart_directory = "sample-cnfs/ndn-multi-db-connections-fail/wordpress"

    resp = Helm.uninstall(release_name)
    helm_install(release_name, helm_chart_directory)
    KubectlClient::Wait.resource_wait_for_install(kind = "Deployment", resource_name = "wordpress", wait_count = 180, namespace = "default")
    violators = Netstat::K8s.get_multiple_pods_connected_to_mariadb_violators
    (Netstat::K8s.detect_multiple_pods_connected_to_mariadb_from_violators(violators)).should be_false
  end

  it "cnf with no database is used by two microservices", tags: ["k8s_netstat"] do
    release_name = "test"
    helm_chart = "bitnami/wordpress"

    Helm.helm_repo_add("bitnami", "https://charts.bitnami.com/bitnami")
    resp = Helm.uninstall(release_name)
    helm_install(release_name, helm_chart, nil, "--set mariadb.primary.persistence.enabled=false --set persistence.enabled=false")
    KubectlClient::Wait.resource_wait_for_install(kind = "Deployment", resource_name = "test-wordpress", wait_count = 180, namespace = "default")
    violators = Netstat::K8s.get_multiple_pods_connected_to_mariadb_violators
    (Netstat::K8s.detect_multiple_pods_connected_to_mariadb_from_violators(violators)).should be_false
  end
end