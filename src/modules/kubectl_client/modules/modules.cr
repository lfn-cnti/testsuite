module KubectlClient
  module Rollout
    @@logger : ::Log = Log.for("Rollout")

    def self.status(kind : String, resource_name : String, namespace : String? = nil, timeout : String = "30s")
      logger = @@logger.for("status")
      logger.info { "Get rollout status of #{kind}/#{resource_name}" }

      cmd = "kubectl rollout status #{kind}/#{resource_name} --timeout=#{timeout}"
      cmd = "#{cmd} -n #{namespace}" if namespace

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.undo(kind : String, resource_name : String, namespace : String? = nil)
      logger = @@logger.for("undo")
      logger.info { "Undo rollout of #{kind}/#{resource_name}" }

      cmd = "kubectl rollout undo #{kind}/#{resource_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end
  end

  module Apply
    @@logger : ::Log = Log.for("Apply")

    def self.resource(kind : String, resource_name : String, namespace : String? = nil, values : String? = nil)
      logger = @@logger.for("resource")
      logger.info { "Apply resource #{kind}/#{resource_name}" }

      cmd = "kubectl apply #{kind}/#{resource_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace
      cmd = "#{cmd} #{values}" if values

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.file(file_name : String?, namespace : String? = nil)
      logger = @@logger.for("file")
      logger.info { "Apply resources from file #{file_name}" }

      cmd = "kubectl apply -f #{file_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.namespace(name : String)
      logger = @@logger.for("namespace")
      logger.info { "Create a namespace: #{name}" }

      cmd = "kubectl create namespace #{name}"

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end
  end

  module Delete
    @@logger : ::Log = Log.for("Delete")

    def self.resource(kind : String, resource_name : String? = nil, namespace : String? = nil,
                      labels : Hash(String, String) = {} of String => String, extra_opts : String? = nil)
      logger = @@logger.for("resource")
      log_str = "Delete resource #{kind}"
      log_str += "/#{resource_name}" if resource_name
      logger.info { "#{log_str}" }

      # resource_name.to_s will expand to "" in case of nil
      cmd = "kubectl delete #{kind} #{resource_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace
      unless labels.empty?
        label_options = labels.map { |key, value| "-l #{key}=#{value}" }.join(" ")
        cmd = "#{cmd} #{label_options}"
      end
      cmd = "#{cmd} #{extra_opts}" if extra_opts

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.file(file_name : String, namespace : String? = nil, wait : Bool = false)
      logger = @@logger.for("file")
      logger.info { "Delete resources from file #{file_name}" }

      cmd = "kubectl delete -f #{file_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace
      if wait
        cmd = "#{cmd} --wait=true"
        logger.info { "Waiting until requested resource is deleted" }
      end

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end
  end

  module Utils
    @@logger : ::Log = Log.for("Utils")

    def self.logs(pod_name : String, container_name : String? = nil, namespace : String? = nil, options : String? = nil)
      logger = @@logger.for("logs")
      logger.debug { "Dump logs of #{pod_name}" }

      cmd = "kubectl logs #{pod_name}"
      cmd = "#{cmd} -c #{container_name}" if container_name
      cmd = "#{cmd} -n #{namespace}" if namespace
      cmd = "#{cmd} #{options}" if options

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    # Exceptions (other than network) not raised in this method as 'command' can be whatever caller desires,
    # unlike other methods in which method body will build a valid command forced by its arguments.
    def self.exec(pod_name : String, command : String, container_name : String? = nil, namespace : String? = nil)
      logger = @@logger.for("exec")
      logger.info { "Exec command in pod #{pod_name}" }

      cmd = "kubectl exec #{pod_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace
      cmd = "#{cmd} -c #{container_name}" if container_name
      cmd = "#{cmd} -- #{command}"

      result = ShellCMD.run(cmd, logger)
      begin
        ShellCMD.raise_exc_on_error { result }
      rescue ex
        if ex.is_a?(KubectlClient::ShellCMD::NetworkError)
          raise ex
        end
      end

      result
    end

    # Use with caution as there is no error handling due to process being started in the background.
    def self.exec_bg(pod_name : String, command : String, container_name : String? = nil, namespace : String? = nil)
      logger = @@logger.for("exec_bg")
      logger.info { "Exec background command in pod #{pod_name}" }

      cmd = "kubectl exec #{pod_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace
      cmd = "#{cmd} -c #{container_name}" if container_name
      cmd = "#{cmd} -- #{command}"

      ShellCMD.new(cmd, logger)
    end

    def self.copy_to_pod(pod_name : String, source : String, destination : String,
                         container_name : String? = nil, namespace : String? = nil)
      logger = @@logger.for("copy_to_pod")
      logger.debug { "Copy #{source} to #{pod_name}:#{destination}" }

      cmd = "kubectl cp"
      cmd = "#{cmd} -n #{namespace}" if namespace
      cmd = "#{cmd} #{source} #{pod_name}:#{destination}"
      cmd = "#{cmd} -c #{container_name}" if container_name

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.copy_from_pod(pod_name : String, source : String, destination : String,
                           container_name : String? = nil, namespace : String? = nil)
      logger = @@logger.for("copy_from_pod")
      logger.debug { "Copy #{pod_name}:#{source} to #{destination}" }

      cmd = "kubectl cp"
      cmd = "#{cmd} -n #{namespace}" if namespace
      cmd = "#{cmd} #{pod_name}:#{source} #{destination}"
      cmd = "#{cmd} -c #{container_name}" if container_name

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.scale(kind : String, resource_name : String, replicas : Int32, namespace : String? = nil)
      logger = @@logger.for("scale")
      logger.info { "Scale #{kind}/#{resource_name} to #{replicas} replicas" }

      cmd = "kubectl scale #{kind}/#{resource_name} --replicas=#{replicas}"
      cmd = "#{cmd} -n #{namespace}" if namespace

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.replace_raw(path : String, file_path : String, extra_flags : String? = nil)
      logger = @@logger.for("replace_raw")
      logger.info { "Replace #{path} with content of #{file_path}" }

      cmd = "kubectl replace --raw '#{path}' -f #{file_path}"
      cmd = "#{cmd} #{extra_flags}" if extra_flags

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.annotate(kind : String, resource_name : String, annotatation_str : String, namespace : String? = nil)
      logger = @@logger.for("annotate")
      logger.info { "Annotate #{kind}/#{resource_name} with #{annotatation_str}" }

      cmd = "kubectl annotate #{kind}/#{resource_name} --overwrite #{annotatation_str}"
      cmd = "#{cmd} -n #{namespace}" if namespace

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.label(kind : String, resource_name : String, labels : Array(String), namespace : String? = nil)
      logger = @@logger.for("label")
      logger.info { "Label #{kind}/#{resource_name} with #{labels.join(",")}" }

      cmd = "kubectl label --overwrite #{kind}/#{resource_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace

      labels.each do |label|
        cmd = "#{cmd} #{label}"
      end

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.cordon(node_name : String)
      logger = @@logger.for("cordon")
      logger.info { "Cordon node #{node_name}" }

      cmd = "kubectl cordon #{node_name}"

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.uncordon(node_name : String)
      logger = @@logger.for("uncordon")
      logger.info { "Uncordon node #{node_name}" }

      cmd = "kubectl uncordon #{node_name}"

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    def self.set_image(
      resource_kind : String,
      resource_name : String,
      container_name : String,
      image_name : String,
      version_tag : String? = nil,
      namespace : String? = nil
    )
      logger = @@logger.for("set_image")
      logger.info { "Set image of container #{resource_kind}/#{resource_name}/#{container_name} to #{image_name}" }

      cmd = version_tag ? 
        "kubectl set image #{resource_kind}/#{resource_name} #{container_name}=#{image_name}:#{version_tag}" :
        "kubectl set image #{resource_kind}/#{resource_name} #{container_name}=#{image_name}"
      cmd = "#{cmd} -n #{namespace}" if namespace

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end
  end
end
