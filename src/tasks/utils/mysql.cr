require "../../modules/cluster_tools"

module Mysql
  MYSQL_PORT = "3306"
  MYSQL_IMAGES = ["mysql/mysql-server", "bitnami/mysql", "bitnamilegacy/mysql"]
  def self.match()
    ClusterTools.local_match_by_image_name_with_retries(MYSQL_IMAGES)
  end
end
