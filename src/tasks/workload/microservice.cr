# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"
require "../utils/docker_client.cr"
require "halite"
require "totem"

desc "The CNF conformance suite checks to see if CNFs follows microservice principles"
task "microservice", ["reasonable_image_size", "reasonable_startup_time"] do |_, args|
  stdout_score("microservice")
end

desc "Does the CNF have a reasonable startup time (< 30 seconds)?"
task "reasonable_startup_time" do |_, args|
  unless check_destructive(args)
    upsert_skipped_task("reasonable_startup_time", "✖️  SKIPPED: skipping reasonable_startup_time: not in destructive mode")
    next
  end
  LOGGING.info "Running reasonable_startup_time in destructive mode!"
  CNFManager::Task.task_runner(args) do |args, config|
    VERBOSE_LOGGING.info "reasonable_startup_time" if check_verbose(args)
    LOGGING.debug "cnf_config: #{config.cnf_config}"

    yml_file_path = config.cnf_config[:yml_file_path]
    helm_chart = config.cnf_config[:helm_chart]
    helm_directory = config.cnf_config[:helm_directory]
    release_name = config.cnf_config[:release_name]
    install_method = config.cnf_config[:install_method]

    current_dir = FileUtils.pwd
    helm = CNFSingleton.helm
    VERBOSE_LOGGING.info helm if check_verbose(args)

    create_namespace = `kubectl create namespace startup-test`
    helm_template_orig = ""
    helm_template_test = ""
    kubectl_apply = ""
    is_kubectl_applied = ""
    is_kubectl_deployed = ""
    # TODO make this work with a manifest installation
    elapsed_time = Time.measure do
      LOGGING.info("reasonable_startup_time helm_chart.empty?: #{helm_chart.empty?}")
      if install_method[0] == :helm_chart
      # unless helm_chart.empty? #TODO make this work for a manifest
        LOGGING.info("reasonable_startup_time #{helm} template #{release_name} #{helm_chart} > #{yml_file_path}/reasonable_startup_orig.yml")
        LOGGING.info "helm_template_orig command: #{helm} template #{release_name} #{helm_chart} > #{yml_file_path}/reasonable_startup_orig.yml}"
        helm_template_orig = `#{helm} template #{release_name} #{helm_chart} > #{yml_file_path}/reasonable_startup_orig.yml`
        LOGGING.info("reasonable_startup_time #{helm} template --namespace=startup-test #{release_name} #{helm_chart} > #{yml_file_path}/reasonable_startup_test.yml")
        helm_template_test = `#{helm} template --namespace=startup-test #{release_name} #{helm_chart} > #{yml_file_path}/reasonable_startup_test.yml`
        VERBOSE_LOGGING.info "helm_chart: #{helm_chart}" if check_verbose(args)
      elsif install_method[0] == :helm_directory
        LOGGING.info("reasonable_startup_time #{helm} template #{release_name} #{CNFManager.helm_dir_path(yml_file_path, helm_directory)} > #{yml_file_path}/reasonable_startup_orig.yml")
        helm_template_orig = `#{helm} template #{release_name} #{CNFManager.helm_dir_path(yml_file_path, helm_directory)} > #{yml_file_path}/reasonable_startup_orig.yml`
        LOGGING.info("reasonable_startup_time #{helm} template --namespace=startup-test #{release_name} #{CNFManager.helm_dir_path(yml_file_path, helm_directory)} > #{yml_file_path}/reasonable_startup_test.yml")
        helm_template_test = `#{helm} template --namespace=startup-test #{release_name} #{CNFManager.helm_dir_path(yml_file_path, helm_directory)} > #{yml_file_path}/reasonable_startup_test.yml`
        VERBOSE_LOGGING.info "helm_directory: #{helm_directory}" if check_verbose(args)
      else # manifest file installation not supported
        puts "Manifest file not supported for reasonable startup time yet".colorize(:yellow)
        raise "Manifest file not supported yet"
      end

      # kubectl_apply = `kubectl apply -f #{yml_file_path}/reasonable_startup_test.yml --namespace=startup-test`
      KubectlClient::Apply.file("#{yml_file_path}/reasonable_startup_test.yml --namespace=startup-test")
      is_kubectl_applied = $?.success?

      template_ymls = Helm::Manifest.parse_manifest_as_ymls("#{yml_file_path}/reasonable_startup_test.yml")

      LOGGING.debug "template_ymls: #{template_ymls}"
      task_response = template_ymls.map do |resource|
        LOGGING.debug "Waiting on resource: #{resource["metadata"]["name"]} of type #{resource["kind"]}"
        if resource["kind"].as_s.downcase == "deployment" ||
            resource["kind"].as_s.downcase == "pod" ||
            resource["kind"].as_s.downcase == "daemonset" ||
            resource["kind"].as_s.downcase == "statefulset" ||
            resource["kind"].as_s.downcase == "replicaset"

          KubectlClient::Get.resource_wait_for_install(resource["kind"].as_s, resource["metadata"]["name"].as_s, wait_count=180, "startup-test")
          $?.success?
        else
          true
        end
      end
      is_kubectl_deployed = task_response.none?{|x| x == false}
    end

    VERBOSE_LOGGING.info helm_template_test if check_verbose(args)
    VERBOSE_LOGGING.info kubectl_apply if check_verbose(args)
    VERBOSE_LOGGING.info "installed? #{is_kubectl_applied}" if check_verbose(args)
    VERBOSE_LOGGING.info "deployed? #{is_kubectl_deployed}" if check_verbose(args)

    emoji_fast="🚀"
    emoji_slow="🐢"
    startup_time_limit = 30
    if ENV["CRYSTAL_ENV"]? == "TEST"
      startup_time_limit = 37 
      LOGGING.info "startup_time_limit TEST mode: #{startup_time_limit}"
    end
    LOGGING.info "startup_time_limit: #{startup_time_limit}"

    if is_kubectl_applied && is_kubectl_deployed && elapsed_time.seconds < startup_time_limit
      upsert_passed_task("reasonable_startup_time", "✔️  PASSED: CNF had a reasonable startup time #{emoji_fast}")
    else
      upsert_failed_task("reasonable_startup_time", "✖️  FAILED: CNF had a startup time of #{elapsed_time.seconds} seconds #{emoji_slow}")
    end

   ensure
    LOGGING.debug "Reasonable startup cleanup"
    delete_namespace = `kubectl delete namespace startup-test --force --grace-period 0 2>&1 >/dev/null`
    # rollback_non_namespaced = `kubectl apply -f #{yml_file_path}/reasonable_startup_orig.yml`
    KubectlClient::Apply.file("#{yml_file_path}/reasonable_startup_orig.yml")
    # KubectlClient::Get.wait_for_install(deployment_name, wait_count=180)
  end
end

desc "Does the CNF have a reasonable container image size (< 5GB)?"
task "reasonable_image_size", ["install_dockerd"] do |_, args|
  unless check_dockerd
    upsert_skipped_task("reasonable_image_size", "✖️  SKIPPED: Skipping reasonable_image_size: Dockerd tool failed to install")
    next
  end
  CNFManager::Task.task_runner(args) do |args,config|
    VERBOSE_LOGGING.info "reasonable_image_size" if check_verbose(args)
    LOGGING.debug "cnf_config: #{config}"
    task_response = CNFManager.workload_resource_test(args, config) do |resource, container, initialized|

      yml_file_path = config.cnf_config[:yml_file_path]

      if resource["kind"].as_s.downcase == "deployment" ||
          resource["kind"].as_s.downcase == "statefulset" ||
          resource["kind"].as_s.downcase == "pod" ||
          resource["kind"].as_s.downcase == "replicaset"
				test_passed = true

				fqdn_image = container.as_h["image"].as_s
        # parsed_image = DockerClient.parse_image(fqdn_image)

        image_pull_secrets = KubectlClient::Get.resource(resource[:kind], resource[:name]).dig?("spec", "template", "spec", "imagePullSecrets")
        if image_pull_secrets
          auths = image_pull_secrets.as_a.map { |secret|
            puts secret["name"]
            secret_data = KubectlClient::Get.resource("Secret", "#{secret["name"]}").dig?("data")
            if secret_data
              dockerconfigjson = Base64.decode_string("#{secret_data[".dockerconfigjson"]}")
              dockerconfigjson.gsub(%({"auths":{),"")[0..-3]
              # parsed_dockerconfigjson = JSON.parse(dockerconfigjson)
              # parsed_dockerconfigjson["auths"].to_json.gsub("{","").gsub("}", "")
            else
              # JSON.parse(%({}))
              ""
            end
          }
          if auths
            str_auths = %({"auths":{#{auths.reduce("") { | acc, x|
            acc + x.to_s + ","
          }[0..-2]}}})
            puts "str_auths: #{str_auths}"
          end
          File.write("#{yml_file_path}/config.json", str_auths)
          KubectlClient.exec("dockerd -ti -- mkdir -p /root/.docker/")
          KubectlClient.cp("#{yml_file_path}/config.json default/dockerd:/root/.docker/config.json")
        end


        KubectlClient.exec("dockerd -ti -- docker pull #{fqdn_image}")
        KubectlClient.exec("dockerd -ti -- docker save #{fqdn_image} -o /tmp/image.tar")
        KubectlClient.exec("dockerd -ti -- gzip -f /tmp/image.tar")
        exec_resp =  KubectlClient.exec("dockerd -ti -- wc -c /tmp/image.tar.gz | awk '{print$1}'")
        compressed_size = exec_resp[:output]
        # TODO strip out secret from under auths, save in array
        # TODO make a new auths array, assign previous array into auths array
        # TODO save auths array to a file
        # dockerhub_image_tags = DockerClient::Get.image_tags(local_image_tag[:image])
        # if dockerhub_image_tags && dockerhub_image_tags.status_code == 200
        #   image_by_tag = DockerClient::Get.image_by_tag(dockerhub_image_tags, local_image_tag[:tag])
        #   micro_size = image_by_tag && image_by_tag["full_size"]
        # else
        #   puts "Failed to find resource: #{resource} and container: #{local_image_tag[:image]}:#{local_image_tag[:tag]} on dockerhub".colorize(:yellow)
        #   test_passed=false
        # end
        LOGGING.info "compressed_size: #{fqdn_image} = '#{compressed_size.to_s}'"
        max_size = 5_000_000_000
        if ENV["CRYSTAL_ENV"]? == "TEST"
           LOGGING.info("Using Test Mode max_size")
           max_size = 16_000_000
        end

        begin
          unless compressed_size.to_s.to_i64 < max_size
            puts "resource: #{resource} and container: #{fqdn_image} was more than #{max_size}".colorize(:red)
            test_passed=false
          end
        rescue ex
          LOGGING.error "invalid compressed_size: #{fqdn_image} = '#{compressed_size.to_s}', #{ex.message}".colorize(:red)
          test_passed = false
        end
      else
        test_passed = true
      end
      test_passed
    end

    emoji_image_size="⚖️👀"
    emoji_small="🐜"
    emoji_big="🦖"

    if task_response
      upsert_passed_task("reasonable_image_size", "✔️  PASSED: Image size is good #{emoji_small} #{emoji_image_size}")
    else
      upsert_failed_task("reasonable_image_size", "✖️  FAILED: Image size too large #{emoji_big} #{emoji_image_size}")
    end
  # ensure
  #   delete_dockerd = `kubectl delete -f #{TOOLS_DIR}/dockerd/manifest.yml`
  end
end


