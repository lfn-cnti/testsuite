module KubectlClient
  module Get
    @@logger : ::Log = Log.for("Get")

    @@schedulable_nodes_template : String = <<-GOTEMPLATE.strip
    {{- range .items -}}
      {{$taints:=""}}
      {{- range .spec.taints -}}
        {{- if eq .effect "NoSchedule" -}}
          {{- $taints = print $taints .key "," -}}
        {{- end -}}
      {{- end -}}
      {{- if not $taints -}}
        {{- .metadata.name}}
        {{- "\\n" -}}
      {{end -}}
    {{- end -}}
    GOTEMPLATE

    def self.resource(kind : String, resource_name : String? = nil, namespace : String? = nil,
                      all_namespaces : Bool = false, field_selector : String? = nil,
                      selector : String? = nil) : JSON::Any
      logger = @@logger.for("resource")
      log_str = "Get resource #{kind}"
      log_str += "/#{resource_name}" if resource_name
      logger.debug { "#{log_str}" }

      # resource_name.to_s will expand to "" in case of nil
      cmd = "kubectl get #{kind} #{resource_name}"
      cmd = "#{cmd} --field-selector #{field_selector}" if field_selector && !resource_name
      cmd = "#{cmd} --selector #{selector}" if selector && !resource_name
      cmd = "#{cmd} -n #{namespace}" if namespace && !all_namespaces
      cmd = "#{cmd} -A" if !namespace && all_namespaces
      cmd = "#{cmd} -o json"

      result = ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }

      if result[:status].success? && !result[:output].empty?
        JSON.parse(result[:output])
      else
        EMPTY_JSON
      end
    end

    def self.privileged_containers(namespace : String? = nil, all_namespaces : Bool? = true) : Array(JSON::Any)
      logger = @@logger.for("privileged_containers")
      logger.debug { "Get privileged containers" }

      pods = resource("pods", namespace: namespace, all_namespaces: all_namespaces).dig("items").as_a
      privileged_containers = pods.map do |pod|
        pod.dig("spec", "containers").as_a.map do |container|
          if container.dig?("securityContext", "privileged") == true
            container
          else
            nil
          end
        end.compact
      end.flatten
      logger.info { "Found #{privileged_containers.size} privileged containers" }

      privileged_containers
    end

    def self.resource_map(k8s_manifest, &)
      nodes = resource("nodes")
      if nodes["items"]?
        items = nodes["items"].as_a.map do |item|
          if nodes["metadata"]?
            metadata = nodes["metadata"]
          else
            metadata = EMPTY_JSON
          end
          yield item, metadata
        end
        items
      else
        [EMPTY_JSON]
      end
    end

    def self.resource_select(&)
      nodes = resource("nodes")
      if nodes["items"]?
        items = nodes["items"].as_a.select do |item|
          if nodes["metadata"]?
            metadata = nodes["metadata"]
          else
            metadata = EMPTY_JSON
          end
          yield item, metadata
        end
        items
      else
        [] of JSON::Any
      end
    end

    def self.resource_select(k8s_manifest, &)
      nodes = resource("nodes")
      if nodes["items"]?
        items = nodes["items"].as_a.select do |item|
          if nodes["metadata"]?
            metadata = nodes["metadata"]
          else
            metadata = EMPTY_JSON
          end
          yield item, metadata
        end
        items
      else
        [] of JSON::Any
      end
    end

    def self.schedulable_nodes_list(retry_limit : Int32 = 20) : Array(JSON::Any)
      logger = @@logger.for("schedulable_nodes_list")
      logger.debug { "Retrieving list of schedulable nodes" }

      retries = 1
      empty_json_any = [] of JSON::Any
      nodes = empty_json_any
      # Get.nodes seems to have failures sometimes
      until (nodes != empty_json_any) || retries > retry_limit
        nodes = resource_select(KubectlClient::Get.resource("nodes")) do |item, _|
          taints = item.dig?("spec", "taints")
          if taints && taints.as_a.find { |x| x.dig?("effect") == "NoSchedule" }
            false
          else
            true
          end
        end
        sleep 1.seconds
        retries = retries + 1
      end

      if nodes == empty_json_any
        logger.notice { "Could not retrieve any schedulable nodes" }
      else
        logger.info { "Retrieved schedulable nodes list: #{KubectlClient.names_from_json_array_to_s(nodes)}" }
      end

      nodes
    end

    def self.nodes_by_resource(resource, retry_limit = 20) : Array(JSON::Any)
      logger = @@logger.for("nodes_by_resource")
      full_resource = "#{resource.dig?("kind")}/#{resource.dig?("metadata", "name")}"
      logger.debug { "Retrieving list of nodes that have resource: #{full_resource}" }

      retries = 1
      empty_json_any = [] of JSON::Any
      nodes = empty_json_any
      # Get.nodes seems to have failures sometimes
      until (nodes != empty_json_any) || retries > retry_limit
        # TODO: matching only by the name might not be enough and this can lead to unexpected behavior
        nodes = KubectlClient::Get.resource_select() do |item, _|
          item.dig?("metadata", "name") == resource.dig?("metadata", "name")
        end
        retries = retries + 1
      end

      if nodes == empty_json_any
        logger.notice { "Could not retrieve any nodes with #{full_resource} present" }
      else
        logger.info { "Nodes with resource #{full_resource} list: #{KubectlClient.names_from_json_array_to_s(nodes)}" }
      end

      nodes
    end

    def self.nodes_by_pod(pod, retry_limit = 3) : Array(JSON::Any)
      logger = @@logger.for("nodes_by_pod")
      pod_name = "#{pod.dig?("metadata", "name")}"
      logger.debug { "Finding nodes with pod/#{pod_name}" }

      retries = 1
      empty_json_any = [] of JSON::Any
      nodes = empty_json_any
      # Get.nodes seems to have failures sometimes
      until (nodes != empty_json_any) || retries > retry_limit
        nodes = KubectlClient::Get.resource_select() do |item, _|
          item.dig?("metadata", "name") == pod.dig?("spec", "nodeName")
        end
        retries = retries + 1
      end

      if nodes == empty_json_any
        logger.notice { "Could not retrieve any node with pod/#{pod_name} present" }
      else
        logger.info { "Nodes with pod/#{pod_name} list: #{KubectlClient.names_from_json_array_to_s(nodes)}" }
      end

      nodes
    end

    def self.pods_by_nodes(nodes_json : Array(JSON::Any))
      logger = @@logger.for("pods_by_nodes")
      logger.debug { "Creating list of pods found on nodes" }

      pods_a = nodes_json.flat_map do |item|
        node_name = item.dig?("metadata", "labels", "kubernetes.io/hostname")
        pods = resource("pods", all_namespaces: true)
        pods = pods.as_h["items"].as_a.select do |pod|
          if pod.dig?("spec", "nodeName") == "#{node_name}"
            pod_name = pod.dig?("metadata", "name")
            true
          else
            false
          end
        end
      end
      logger.info { "Found #{pods_a.size} pods: #{KubectlClient.names_from_json_array_to_s(pods_a)}" }

      pods_a
    end

    # TODO: (rafal-lal) if namespace not provided, automatically assume all_namespaces rather than default ->
    # make sure that is the case throughout the codebase
    def self.pods_by_resource_labels(resource_json : JSON::Any, namespace : String? = nil) : Array(JSON::Any)
      logger = @@logger.for("pods_by_resource_labels")
      kind = resource_json["kind"]?
      name = resource_json["metadata"]["name"]?
      logger.debug { "Creating list of pods by resource: #{kind}/#{name} labels" }

      return [resource_json] if resource_json["kind"].as_s.downcase == "pod"
      if !name || !kind
        logger.warn { "Passed resource is nil" }
        return [] of JSON::Any
      end

      if namespace.nil?
        pods = resource("pods", all_namespaces: true)["items"].as_a
      else
        pods = resource("pods", namespace: namespace)["items"].as_a
      end

      # todo deployment labels may not match template metadata labels.
      # -- may need to match on selector matchlabels instead
      labels = resource_spec_labels(resource_json["kind"].as_s, name.as_s, namespace: namespace).as_h
      filtered_pods = pods_by_labels(pods, labels)

      filtered_pods
    end

    def self.pods_by_labels(pods_json : Array(JSON::Any), labels : Hash(String, JSON::Any))
      logger = @@logger.for("pods_by_labels")
      logger.debug { "Creating list of pods that have labels: #{labels}" }

      pods_json = pods_json.select do |pod|
        if labels == Hash(String, JSON::Any).new
          match = false
        else
          match = true
        end
        # todo deployment labels may not match template metadata labels.
        # -- may need to match on selector matchlabels instead
        labels.map do |key, value|
          if pod.dig?("metadata", "labels", key) == value
            match = true
          else
            match = false
          end
        end
        match
      end
      logger.info { "Matched #{pods_json.size} pods: #{KubectlClient.names_from_json_array_to_s(pods_json)}" }

      pods_json
    end

    def self.pods_by_labels(pods_json : Array(JSON::Any), labels : Hash(String, String))
      logger = @@logger.for("pods_by_labels")
      logger.debug { "Creating list of pods that have labels: #{labels}" }

      pods_json = pods_json.select do |pod|
        if labels == Hash(String, String).new
          match = false
        else
          match = true
        end
        # todo deployment labels may not match template metadata labels.
        # -- may need to match on selector matchlabels instead
        labels.map do |key, value|
          if pod.dig?("metadata", "labels", key) == value
            match = true
          else
            match = false
          end
        end
        match
      end
      logger.debug { "Matched #{pods_json.size} pods: #{KubectlClient.names_from_json_array_to_s(pods_json)}" }

      pods_json
    end

    def self.service_by_pod(pod) : JSON::Any?
      logger = @@logger.for("service_by_pod")
      pod_name = pod.dig("metadata", "name")
      logger.debug { "Matching pod: #{pod_name} to service" }

      services = KubectlClient::Get.resource("service", all_namespaces: true)
      matched_service : JSON::Any? = nil
      services["items"].as_a.each do |service|
        service_labels = service.dig?("spec", "selector")
        next unless service_labels

        pods = KubectlClient::Get.resource("pods", all_namespaces: true)
        service_pods = KubectlClient::Get.pods_by_labels(pods["items"].as_a, service_labels.as_h)
        service_pods.each do |service_pod|
          service_name = service_pod.dig("metadata", "name")
          matched_service = service if service_name == pod_name
        end
      end

      if matched_service.nil?
        logger.notice { "Could not match pod to any service" }
        return matched_service
      end
      logger.info { "Pod: #{pod_name} matched to service: #{matched_service.dig("metadata", "name").as_s}" }

      matched_service
    end

    def self.pods_by_service(service) : Array(JSON::Any)?
      logger = @@logger.for("pods_by_service")
      logger.debug { "Matching pods to service: #{service.dig?("metadata", "name")}" }

      service_labels = service.dig?("spec", "selector")
      return unless service_labels

      pods = KubectlClient::Get.resource("pods")
      service_pods = KubectlClient::Get.pods_by_labels(pods["items"].as_a, service_labels.as_h)
    end

    def self.pods_by_digest(container_digest) : Array(JSON::Any)
      logger = @@logger.for("pods_by_digest")
      logger.debug { "Matching pods to digest: #{container_digest}" }

      matched_pods = [] of JSON::Any
      pods = KubectlClient::Get.resource("pods", all_namespaces: true)
      pods["items"].as_a.each do |pod|
        statuses = pod.dig?("status", "containerStatuses")
        if statuses
          statuses.as_a.each do |status|
            matched_pods << pod if status.dig("imageID").as_s.includes?("#{container_digest}")
          end
        end
      end
      logger.info { "Matched #{matched_pods.size} pods: #{KubectlClient.names_from_json_array_to_s(matched_pods)}" }

      matched_pods
    end

    def self.resource_containers(kind : String, resource_name : String, namespace : String? = nil) : JSON::Any
      logger = @@logger.for("resource_containers")
      logger.debug { "Get containers of #{kind}/#{resource_name}" }

      case kind.downcase
      when "pod"
        resp = resource(kind, resource_name, namespace).dig?("spec", "containers")
      when "deployment", "statefulset", "replicaset", "daemonset"
        resp = resource(kind, resource_name, namespace).dig?("spec", "template", "spec", "containers")
      end

      return EMPTY_JSON_ARRAY if resp.nil?
      return resp
    end

    def self.resource_volumes(kind : String, resource_name : String, namespace : String? = nil) : JSON::Any
      logger = @@logger.for("resource_volumes")
      logger.debug { "Get volumes of #{kind}/#{resource_name}" }

      case kind.downcase
      when "pod"
        resp = resource(kind, resource_name, namespace).dig?("spec", "volumes")
      when "deployment", "statefulset", "replicaset", "daemonset"
        resp = resource(kind, resource_name, namespace).dig?("spec", "template", "spec", "volumes")
      end

      return EMPTY_JSON_ARRAY if resp.nil?
      return resp
    end

    def self.replica_count(
      kind : String, resource_name : String, namespace : String? = nil
    ) : NamedTuple(current: Int32, desired: Int32, unavailable: Int32)
      logger = @@logger.for("replica_count")
      logger.debug { "Get replica count of #{kind}/#{resource_name}" }

      resource_json = resource(kind, resource_name, namespace)
      case kind.downcase
      when "replicaset", "deployment", "statefulset"
        current_json = resource_json.dig?("status", "readyReplicas")
        desired_json = resource_json.dig?("status", "replicas")
        unavailable_json = resource_json.dig?("status", "unavailableReplicas")
      when "daemonset"
        current_json = resource_json.dig?("status", "numberAvailable")
        desired_json = resource_json.dig?("status", "desiredNumberScheduled")
        unavailable_json = resource_json.dig?("status", "unavailableReplicas")
      end

      current = desired = unavailable = -1
      current = current_json.to_s.to_i if !current_json.nil?
      desired = desired_json.to_s.to_i if !desired_json.nil?
      unavailable = unavailable_json.to_s.to_i if !unavailable_json.nil?

      logger.trace { "replicas: current = #{current}, desired = #{desired}, unavailable = #{unavailable}" }

      {current: current, desired: desired, unavailable: unavailable}
    end

    # TODO (rafal-lal): add spec for this method
    def self.match_pods_by_prefix(
      pod_name_prefix : String, field_selector : String? = nil, namespace : String? = nil
    ) : Array(String)
      logger = @@logger.for("match_pods_by_prefix")
      logger.debug { "Get pods with with prefix: #{pod_name_prefix} with field selector: #{field_selector}" }

      all_pods_json = resource("pods", namespace: namespace, field_selector: field_selector)
      return [] of String if all_pods_json.dig?("items").nil?

      all_pods = all_pods_json.dig("items").as_a
        .select do |pod_json|
          begin
            pod_name = pod_json.dig("metadata", "name").as_s.strip
            /#{pod_name_prefix}/.match(pod_name) != nil
          rescue ex
            logger.error { "exception rescued: #{ex}" }
            false
          end
        end
        .map { |pod_json| pod_json.dig("metadata", "name").as_s }

      logger.info { "Matched pods: #{all_pods.join(", ")}" }

      all_pods
    end

    def self.pod_ready?(pod_name_prefix : String, field_selector : String? = nil, namespace : String? = nil) : Bool
      logger = @@logger.for("pod_status")
      logger.debug { "Get status of pod/#{pod_name_prefix}* with field selector: #{field_selector}" }

      all_pods_json = resource("pods", namespace: namespace, field_selector: field_selector)
      return false if all_pods_json.dig?("items").nil?

      all_pods = all_pods_json.dig("items").as_a
        .select do |pod_json|
          begin
            pod_name = pod_json.dig("metadata", "name").as_s.strip
            all_ready = pod_json.dig("status", "containerStatuses").as_a.all? { |cstatus| cstatus.dig("ready") == true }
            /#{pod_name_prefix}/.match(pod_name) && all_ready
          rescue ex
            logger.error { "exception rescued: #{ex}" }
            false
          end
        end
        .map { |pod_json| pod_json.dig("metadata", "name").as_s }

      logger.info { "'Ready' pods: #{all_pods.join(", ")}" }
      all_pods.size > 0 ? true : false
    end

    def self.node_ready?(node_name : String) : Bool
      logger = @@logger.for("node_ready?")
      logger.debug { "Check if node status is: Ready" }

      cmd = "kubectl get nodes #{node_name} -o jsonpath='{.status.conditions[?(@.type == \"Ready\")].status}'"
      result = ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }

      result[:output].downcase == "true"
    end

    def self.resource_spec_labels(kind : String, resource_name : String, namespace : String? = nil) : JSON::Any
      logger = @@logger.for("resource_spec_labels")
      logger.debug { "Get labels of resource #{kind}/#{resource_name}" }

      case kind.downcase
      when "service"
        resp = resource(kind, resource_name, namespace: namespace).dig?("spec", "selector")
      when "deployment", "statefulset", "replicaset", "daemonset", "job"
        resp = resource(kind, resource_name, namespace: namespace).dig?("spec", "selector", "matchLabels")
      else
        resp = resource(kind, resource_name, namespace: namespace).dig?("spec", "template", "metadata", "labels")
      end
      logger.trace { "Resource labels: #{resp}" }

      return resp if resp
      return EMPTY_JSON
    end

    def self.container_image_tags(containers : JSON::Any) : Array(NamedTuple(image: String, tag: String))
      logger = @@logger.for("container_image_tags")
      logger.debug { "Get image tags of containers" }

      image_tags = containers.as_a.map do |container|
        {
          image: container.as_h["image"].as_s.rpartition(":")[0],
          tag:   container.as_h["image"].as_s.rpartition(":")[2]?,
        }
      end
      logger.trace { "images and tags: #{image_tags}" }

      image_tags
    end

    def self.worker_nodes : Array(String)
      logger = @@logger.for("worker_nodes")
      logger.debug { "Get list of worker nodes" }

      cmd = "kubectl get nodes --selector='!node-role.kubernetes.io/master' " +
            "-o 'go-template=#{@@schedulable_nodes_template}'"
      result = ShellCMD.raise_exc_on_error { ShellCMD.run(cmd, logger) }

      result[:output].split("\n")
    end

    def self.pv_items_by_claim_name(claim_name : String) : Array(JSON::Any)
      logger = @@logger.for("pv_items_by_claim_name")
      logger.debug { "Get PV items by claim name: #{claim_name}" }

      items = resource("pv")["items"].as_a.map do |x|
        begin
          if x["spec"]["claimRef"]["name"] == claim_name
            x
          else
            nil
          end
        rescue ex
          logger.warn { "Caught exception: #{ex.message}" }
          nil
        end
      end.compact
      logger.trace { "PV items found: #{items}" }

      items
    end

    def self.container_runtimes
      logger = @@logger.for("container_runtimes")
      logger.debug { "Get container runtimes of nodes" }

      nodes = resource("nodes")
      runtimes = nodes["items"].as_a.map do |x|
        x["status"]["nodeInfo"]["containerRuntimeVersion"].as_s
      end
      logger.trace { "runtimes found: #{runtimes.uniq}" }

      runtimes.uniq
    end
  end
end
