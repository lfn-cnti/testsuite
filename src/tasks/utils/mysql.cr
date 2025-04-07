require "../../modules/cluster_tools"

module Mysql
  MYSQL_PORT = "3306" 
  MYSQL_IMAGES = ["mysql/mysql-server","bitnami/mysql"]
  def self.match()
    ClusterTools.local_match_by_image_name(MYSQL_IMAGES)
    # ClusterTools.local_match_by_image_name("bitnami/mysql")
  end
  def self.uninstall
    Log.debug { "uninstall_mysql" }
    begin
      KubectlClient::Delete.file("https://raw.githubusercontent.com/mysql/mysql-operator/trunk/samples/sample-cluster.yaml --wait=false")
    rescue ex: KubectlClient::ShellCMD::NotFoundError
      Log.warn { "Cannot delete \"https://raw.githubusercontent.com/mysql/mysql-operator/trunk/samples/sample-cluster.yaml\". File not found." }
    end
    Helm.uninstall("mysql-operator", "mysql-operator")
  end

  # todo make this work without having the test-suite src
  def self.install
    Log.info {"Installing mysql-operator "}
    Helm.install("mysql-operator", "sample-cnfs/mysql/mysql-operator/helm/mysql-operator", namespace: mysql-operator, create_namespace: true)
    temp_pw = Random.rand.to_s

    KubectlClient::Apply.resource("secret", "generic", values: %|--from-literal=rootUser=root --from-literal=rootHost=% --from-literal=rootPassword="#{temp_pw}"|)
    KubectlClient::Apply.file("https://raw.githubusercontent.com/mysql/mysql-operator/trunk/samples/sample-cluster.yaml")
    KubectlClient::Wait.resource_wait_for_install("Pod", "mycluster-2")
    temp_pw
  end


end

