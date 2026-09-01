NODE_DRAIN_TOTAL_CHAOS_DURATION = ENV.has_key?("CNTI_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION") ? ENV["CNTI_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION"].to_i : 90

class ChaosTemplates
  class PodIoStress
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @target_pod_name : String,
      @total_chaos_duration : String = "120"
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
      @deployment_label : String,
      @deployment_label_value : String
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/disk_fill.yml.ecr")
  end

  class PodDelete
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
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
      @deployment_label : String,
      @deployment_label_value : String,
      @target_pod_name : String,
      @total_chaos_duration : String = "60"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_memory_hog.yml.ecr")
  end

  class NodeDrain
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @app_label : String,
      @app_nodename : String,
      @total_chaos_duration : String = "#{NODE_DRAIN_TOTAL_CHAOS_DURATION}"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/node_drain.yml.ecr")
  end

  class PodDnsError
    def initialize(
      @test_name : String,
      @chaos_experiment_name : String,
      @app_namespace : String,
      @deployment_label : String,
      @deployment_label_value : String,
      @total_chaos_duration : String = "120"
    )
    end
    ECR.def_to_s("src/templates/chaos_templates/pod_dns_error.yml.ecr")
  end
end
