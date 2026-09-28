module CNFInstall
  abstract class DeploymentManager
    property deployment_name : String,
             deployment_priority : Int32

    # True from the moment install hands something to the cluster (kubectl
    # apply, helm install), whether that succeeded or not. An install that
    # fails before, a chart that cannot be pulled for one, has left nothing
    # behind that cnf_uninstall would have to remove.
    getter? cluster_touched : Bool = false

    abstract def install
    abstract def uninstall
    abstract def generate_manifest
    
    def initialize(deployment_name, deployment_priority)
      @deployment_name = deployment_name
      @deployment_priority = deployment_priority
    end
  end
end