module KubectlClient
  # Using sleep() to wait for terminating resources is unreliable.
  #
  # 1. Resources still in terminating state can interfere with test runs.
  #    and result in failures of the next test (or spec test).
  #
  # 2. Helm uninstall wait option and kubectl delete wait options,
  #    do not wait for child resources to be fully deleted.
  #
  # 3. The output from kubectl json does not clearly indicate when a resource is in a terminating state.
  #    To wait for uninstall, we can use the app.kubernetes.io/name label,
  #    to lookup resources belonging to a CNF to wait for uninstall.
  #    We only use this helper in the spec tests, so we use the "kubectl get" output to keep things simple.
  #
  module Wait
    @@logger : ::Log = Log.for("wait")

    def self.wait_for_terminations(namespace : String? = nil, wait_count : Int32 = 30) : Bool
      logger = @@logger.for("wait_for_terminations")
      logger.debug { "Wait for terminations in ns #{namespace}" }

      cmd = "kubectl get all"
      # Check all namespaces by default
      cmd = namespace ? "#{cmd} -n #{namespace}" : "#{cmd} -A"

      # By default assume there is a resource still terminating.
      found_terminating = true
      second_count = 0
      while found_terminating && second_count < wait_count
        result = ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
        if result[:output].match(/([\s+]Terminating)/)
          found_terminating = true
          second_count = second_count + 1
          sleep(1)
        else
          found_terminating = false
          return true
        end

        if second_count % RESOURCE_WAIT_LOG_INTERVAL == 0
          logger.info { "Waiting until resources are terminated, seconds elapsed: #{second_count}" }
        end
      end
      false
    end

    def self.wait_for_condition(
      kind : String, resource_name : String, condition : String, wait_count : Int32 = 180, namespace : String? = nil
    )
      logger = @@logger.for("wait_for_condition")
      logger.info { "Wait for condition #{condition} in #{kind}/#{resource_name}" }

      cmd = "kubectl wait #{kind}/#{resource_name} --for=#{condition} --timeout=#{wait_count}s"
      cmd = "#{cmd} -n #{namespace}" if namespace

      ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }
    end

    private def self.resource_ready?(kind : String, resource_name : String, namespace : String? = nil) : Bool
      logger = @@logger.for("resource_ready?")
      logger.debug { "Checking if resource #{kind}/#{resource_name} is ready" }

      ready = false
      case kind.downcase
      when "pod"
        return KubectlClient::Get.pod_ready?(resource_name, namespace: namespace)
      else
        replicas = KubectlClient::Get.replica_count(kind, resource_name, namespace)
        ready = replicas[:current] == replicas[:desired]
        if replicas[:desired] == 0 && replicas[:unavailable] >= 1
          ready = false
        end
        if replicas[:current] == -1 || replicas[:desired] == -1
          ready = false
        end
      end

      ready
    end

    def self.wait_for_resource_key_value(
      kind : String,
      resource_name : String,
      dig_params : Tuple,
      value : String? = nil,
      wait_count : Int32 = 180,
      namespace : String = "default",
    ) : Bool
      logger = @@logger.for("wait_for_resource_key_value")
      logger.info { "Waiting for resource #{kind}/#{resource_name} to have #{dig_params.join(".")} = #{value}" }

      # Check if resource is installed / ready to use
      case kind.downcase
      when "pod", "replicaset", "deployment", "statefulset", "daemonset"
        is_ready = resource_wait_for_install(kind, resource_name, wait_count, namespace)
      else
        # If not any of the above resources, then assume resource is available.
        is_ready = true
      end

      # Check if key-value condition is met
      resource = KubectlClient::Get.resource(kind, resource_name, namespace)
      is_key_ready = false
      if is_ready
        is_key_ready = wait_for_key_value(resource, dig_params, value, wait_count)
      else
        is_key_ready = false
      end

      is_key_ready
    end

    def self.resource_wait_for_install(
      kind : String,
      resource_name : String,
      wait_count : Int32 = 180,
      namespace : String = "default",
    ) : Bool
      logger = @@logger.for("resource_wait_for_install")
      logger.info { "Waiting for resource #{kind}/#{resource_name} to install" }

      second_count = 0
      is_ready = resource_ready?(kind, resource_name, namespace)
      until is_ready || second_count > wait_count
        if second_count % RESOURCE_WAIT_LOG_INTERVAL == 0
          logger.info { "seconds elapsed while waiting: #{second_count}" }
        end

        sleep 1.seconds
        is_ready = resource_ready?(kind, resource_name, namespace)
        second_count += 1
      end

      if is_ready
        logger.info { "#{kind}/#{resource_name} is ready" }
      else
        logger.warn { "#{kind}/#{resource_name} is not ready and #{wait_count}s elapsed" }
      end

      is_ready
    end

    def self.resource_wait_for_uninstall(
      kind          : String,
      resource_name : String,
      labels        : Hash(String, String) = {} of String => String,
      namespace     : String? = "default",
      wait_count    : Int32   = GENERIC_OPERATION_TIMEOUT
    ) : Bool
      logger = @@logger.for("resource_wait_for_uninstall")
      logger.info { "Waiting for resource #{kind}/#{resource_name} to uninstall" }
    
      seconds_count = 0
      deleted_once = false
    
      # Initial fetch (marks deleted_once if missing up front)
      resource =
        begin
          KubectlClient::Get.resource(kind, resource_name, namespace)
        rescue KubectlClient::ShellCMD::NotFoundError
          deleted_once = true
          EMPTY_JSON
        end
    
      until seconds_count > wait_count
        if seconds_count % RESOURCE_WAIT_LOG_INTERVAL == 0
          logger.info { "seconds elapsed while waiting: #{seconds_count}" }
        end
    
        # Only call Get.resource until we see it NotFound
        present = if !deleted_once
          begin
            KubectlClient::Get.resource(kind, resource_name, namespace)
            true
          rescue KubectlClient::ShellCMD::NotFoundError
            deleted_once = true
            false
          end
        else
          false
        end
    
        # Once parent is gone, look for any leftover pods
        pods = if !present
          all_pods = KubectlClient::Get.resource("pods", nil, namespace).dig("items").as_a
          KubectlClient::Get.pods_by_labels(all_pods, labels)
        elsif resource != EMPTY_JSON
          begin
            KubectlClient::Get.pods_by_resource_labels(resource, namespace)
          rescue KubectlClient::ShellCMD::NotFoundError
            [] of JSON::Any
          end
        else
          [] of JSON::Any
        end
    
        if !present && pods.empty?
          logger.info { "#{kind}/#{resource_name} fully deleted" }
          return true
        end
    
        sleep 1.second
        seconds_count += 1
      end
    
      logger.warn { "#{kind}/#{resource_name} still present after #{wait_count}s" }
      false
    end

    private def self.wait_for_key_value(resource : JSON::Any,
                                        dig_params : Tuple,
                                        value : (String?) = nil,
                                        wait_count : Int32 = 15)
      logger = @@logger.for("wait_for_key_value")

      second_count = 0
      key_created = false
      value_matched = false
      until (key_created && value_matched) || second_count > wait_count.to_i
        if second_count % RESOURCE_WAIT_LOG_INTERVAL == 0
          logger.info { "seconds elapsed while waiting: #{second_count}" }
        end

        sleep 3.seconds
        namespace = resource.dig?("metadata", "namespace")
        if namespace
          resource = KubectlClient::Get.resource(resource["kind"].as_s, resource.dig("metadata", "name").as_s)
        else
          resource = KubectlClient::Get.resource(resource["kind"].as_s, resource.dig("metadata", "name").as_s,
            namespace: namespace)
        end

        if resource.dig?(*dig_params)
          key_created = true

          if value == nil
            value_matched = true
          elsif value == "#{resource.dig(*dig_params)}"
            value_matched = true
          end
        end

        second_count += 1
      end

      key_created && value_matched
    end

    def self.wait_for_install_by_apply(manifest_file : String, wait_count : Int32 = 180) : Bool
      logger = @@logger.for("wait_for_install_by_apply")
      logger.info { "Waiting for manifest found in #{manifest_file} to install" }

      apply_result = KubectlClient::Apply.file(manifest_file)
      apply_resp = apply_result[:output]

      second_count = 0
      until (apply_resp =~ /unchanged/) != nil || second_count > wait_count.to_i
        if second_count % RESOURCE_WAIT_LOG_INTERVAL == 0
          logger.info { "seconds elapsed while waiting: #{second_count}" }
        end

        sleep 1.seconds
        apply_result = KubectlClient::Apply.file(manifest_file)
        apply_resp = apply_result[:output]
        second_count += 1
      end

      if (apply_resp =~ /unchanged/) != nil
        logger.info { "Manifest #{manifest_file} is installed" }
        return true
      end

      logger.warn { "Manifest #{manifest_file} was not installed - timeout" }
      false
    end

    def self.wait_for_resource_availability(kind : String,
                                            resource_name : String,
                                            namespace = "default",
                                            wait_count : Int32 = 180) : Bool
      logger = @@logger.for("wait_for_resource_availability")
      logger.info { "Waiting for #{kind}/#{resource_name} to be available" }

      second_count = 0
      resource_created = false
      until resource_created || (second_count > wait_count.to_i)
        if second_count % RESOURCE_WAIT_LOG_INTERVAL == 0
          logger.info { "seconds elapsed while waiting: #{second_count}" }
        end

        sleep 3.seconds
        resource_created = resource_ready?(kind, resource_name, namespace)
        second_count += 3
      end

      resource_created
    end
  end
end
