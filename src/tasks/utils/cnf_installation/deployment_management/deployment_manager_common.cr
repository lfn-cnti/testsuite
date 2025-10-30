module CNFInstall
  abstract class DeploymentManager
    property deployment_name : String,
             deployment_priority : Int32

    abstract def install
    abstract def uninstall
    abstract def generate_manifest
    
    def initialize(deployment_name, deployment_priority)
      @deployment_name = deployment_name
      @deployment_priority = deployment_priority
    end
  end
end