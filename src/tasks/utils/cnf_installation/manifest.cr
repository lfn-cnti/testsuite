module CNFInstall
  module Manifest
    def self.manifest_path_to_ymls(manifest_path)
      manifest = File.read(manifest_path)
      manifest_string_to_ymls(manifest)
    end

    def self.manifest_string_to_ymls(manifest_string)
      split_content = manifest_string.split(/(\s|^)---(\s|$)/)
      ymls = split_content.map { |manifest|
        YAML.parse(manifest)
      # compact seems to have problems with yaml::any
      }.reject { |x| x == nil }
      Log.for("manifest_string_to_ymls").trace { "YAMLs parsed from string:\n #{ymls}" }
      ymls
    end

    def self.manifest_file_list(manifest_directory, raise_ex = false)
      logger = Log.for("manifest_file_list")

      logger.debug { "Look for manifest files in: '#{manifest_directory}'" }
      if manifest_directory && !manifest_directory.empty? && manifest_directory != "/"
        manifests = find_files("#{manifest_directory}/", "\"*.yml\" -o -name \"*.yaml\"")
        logger.debug { "Found manifests: #{manifests}" }
        if manifests.size == 0 && raise_ex
          raise "No manifest YAMLs found in the #{manifest_directory} directory!"
        end
        manifests
      else
        [] of String
      end
    end

    def self.combine_ymls_as_manifest_string(ymls : Array(YAML::Any)) : String
      manifest = ymls.map { |yaml_object| yaml_object.to_yaml }.join
      Log.for("combine_ymls_as_manifest_string").trace { "YAMLs combined to string:\n #{manifest}" }
      manifest
    end

    # Apply namespaces only to resources that are retrieved from Kubernetes as namespaced resource kinds.
    # Namespaced resource kinds are utilized exclusively during the Helm installation process.
    def self.add_namespace_to_resources(manifest_string, namespace)
      logger = Log.for("add_namespace_to_resources")
      logger.info { "Updating metadata.namespace field for resources in generated manifest" }

      namespaced_resources = KubectlClient::ShellCMD.run(
        "kubectl api-resources --namespaced=true --no-headers", logger).[:output]
      list_of_namespaced_resources = namespaced_resources.split("\n").select { |item| !item.empty? }
      list_of_namespaced_kinds = list_of_namespaced_resources.map { |line| line.split(/\s+/).last }
      parsed_manifest = manifest_string_to_ymls(manifest_string)
      ymls = [] of YAML::Any

      parsed_manifest.each do |resource|
        if resource["kind"].as_s.in?(list_of_namespaced_kinds)
          Helm.ensure_resource_with_namespace(resource, namespace)
          logger.debug { "Added #{namespace} namespace for resource: " +
            "{kind: #{resource["kind"]}, name: #{resource["metadata"]["name"]}}" }
        end
        ymls << resource
      end

      string_manifest_with_namespaces = combine_ymls_as_manifest_string(ymls)
      string_manifest_with_namespaces
    end

    def self.add_manifest_to_file(deployment_name : String, manifest : String, destination_file)
      File.open(destination_file, "a+") do |file|
        file.puts manifest
        Log.for("add_manifest_to_file").debug { "#{deployment_name} manifest was " +
          "appended into #{destination_file} file" }
      end
    end
  end
end
