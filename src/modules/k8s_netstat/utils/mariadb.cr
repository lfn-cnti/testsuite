require "../../cluster_tools"

module Netstat
  module Mariadb
    MYSQL_PORT = "3306" 
    def self.match()
      ClusterTools.local_match_by_image_name("bitnamilegacy/mariadb")
    end
    # def self.uninstall
    #   Log.for("verbose").info { "uninstall_mysql" } 
    #   KubectlClient::Delete.file("https://raw.githubusercontent.com/mysql/mysql-operator/trunk/samples/sample-cluster.yaml --wait=false")
    #   Helm.delete("mysql-operator --namespace mysql-operator")
    # end

    # # todo make this work without having the test-suite src
    # def self.install
    #   Log.info {"Installing mysql-operator "}
    #   Helm.install("mysql-operator sample-cnfs/mysql/mysql-operator/helm/mysql-operator --namespace mysql-operator  --create-namespace ")
    #   temp_pw = Random.rand.to_s
    #   KubectlClient::Create.command(%(secret generic mypwds --from-literal=rootUser=root --from-literal=rootHost=% --from-literal=rootPassword="#{temp_pw}"))
    #   KubectlClient::Apply.file("https://raw.githubusercontent.com/mysql/mysql-operator/trunk/samples/sample-cluster.yaml")
    #   KubectlClient::Get.resource_wait_for_install("Pod", "mycluster-2")
    #   # KubectlClient::Get.resource_wait_for_install("Pod", "jaeger-hotrod")
    #   # KubectlClient::Get.resource_wait_for_install("Deployment", "jaeger-query")
    #   # KubectlClient::Get.resource_wait_for_install("Daemonset", "jaeger-agent")
    #   temp_pw
    # end
  end
end