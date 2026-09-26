
class ChaosTemplates
  class PodIoStress
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @target_pod_name : String,
      @total_chaos_duration : String = "120",
      @container_runtime : String = "containerd",
      @socket_path : String = "/run/containerd/containerd.sock",
      @target_container : String = "",
      @filesystem_utilization_percentage : String = "",
      @volume_mount_path : String = ""
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_io_stress.yml.ecr")
  end

  class Network
    def initialize(@labels)
    end
    ECR.def_to_s("src/templates/chaos_templates/network.yml.ecr")
  end

  class Cpu
    def initialize(@labels)
    end
    ECR.def_to_s("src/templates/chaos_templates/cpu.yml.ecr")
  end

  class PodNetworkLatency
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @total_chaos_duration : String = "60"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_network_latency.yml.ecr")
  end

  class PodNetworkCorruption
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @total_chaos_duration : String = "60"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_network_corruption.yml.ecr")
  end

  class PodNetworkDuplication
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @total_chaos_duration : String = "60"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_network_duplication.yml.ecr")
  end

  class DiskFill
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @target_container : String = ""
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/disk_fill.yml.ecr")
  end

  class PodDelete
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @target_pod_name : String,
      @total_chaos_duration : String = "30"
      
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_delete.yml.ecr")
  end

  class PodMemoryHog
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @target_pod_name : String,
      @total_chaos_duration : String = "60"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_memory_hog.yml.ecr")
  end

  class PodDnsError
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_kind : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @total_chaos_duration : String = "120",
      @container_runtime : String = "containerd",
      @socket_path : String = "/run/containerd/containerd.sock"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_dns_error.yml.ecr")
  end
end
