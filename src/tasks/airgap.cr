require "sam"
require "file_utils"
require "../modules/cluster_tools"
require "./utils/utils.cr"
require "./utils/image_tag.cr"
require "./utils/litmus_manager.cr"
require "./setup/constants.cr"

# Helpers for the air-gap bundle: the files airgap_prepare downloads on a
# connected host and the image references a disconnected cluster needs.
module Airgap
  IMAGE_LINE         = /^\s*(?:-\s*)?image:\s*["']?([^"'\s]+)["']?(?:\s+#.*)?\s*$/
  RUNNER_IMAGE_VALUE = /name:\s*CHAOS_RUNNER_IMAGE\s*\n\s*value:\s*["']?([^"'\s]+)["']?/
  # A --cnf-config at the root of a checkout must not send the scan through the
  # whole repository (or the run's own cnti/ workspace, which is scanned as
  # CNF_DIR when the CNF is installed).
  SKIP_DIRS = [".git", "node_modules", "vendor", "target", "cnti"]

  def self.fault_url(fault : String) : String
    "#{LitmusManager.chaos_charts}/faults/kubernetes/#{fault}/fault.yaml"
  end

  def self.host_artifacts : Array(String)
    [Setup::HELM_URL,
     Setup::KUBESCAPE_URL,
     Setup::KUBESCAPE_FRAMEWORK_URL,
     Setup::KUBESCAPE_CONTROLS_URL,
     Kyverno.download_url,
     LitmusManager::LITMUS_OPERATOR] +
      LitmusManager::FAULTS.map { |fault| fault_url(fault) }
  end

  def self.fault_manifests : Array(String)
    LitmusManager::FAULTS.map { |fault| Offline.cache_path(fault_url(fault)) }
  end

  def self.headers_for(url : String) : HTTP::Headers?
    return nil unless url.includes?("github.com") || url.includes?("githubusercontent.com")
    token = ENV["GITHUB_TOKEN"]?
    return nil if token.nil? || token.empty?
    HTTP::Headers{"Authorization" => "Bearer #{token}"}
  end

  # The image references in a YAML stream, from both "image: x" and "- image: x".
  # The Litmus operator also names its runner in an environment variable.
  def self.images_from_yaml(content : String) : Array(String)
    images = content.lines.compact_map do |line|
      match = line.match(IMAGE_LINE)
      next unless match
      image = match[1].strip
      next if image.empty? || image.includes?("{{")
      image
    end
    if match = content.match(RUNNER_IMAGE_VALUE)
      images << match[1]
    end
    images
  end

  # The container name and image of each container declared in a YAML stream.
  # Compatibility tests take a configured tag and apply it to that deployed
  # image's repository, so the bundle needs the resulting image reference too.
  def self.container_images_from_yaml(content : String) : Array(NamedTuple(name: String, image: String))
    found = [] of NamedTuple(name: String, image: String)
    YAML.parse_all(content).each { |document| container_images_in(document, found) }
    found
  rescue YAML::ParseException
    [] of NamedTuple(name: String, image: String)
  end

  private def self.container_images_in(node : YAML::Any, found : Array(NamedTuple(name: String, image: String))) : Nil
    if hash = node.as_h?
      name = hash["name"]?.try(&.as_s?)
      image = hash["image"]?.try(&.as_s?)
      if name && image && !image.includes?("{{")
        found << {name: name, image: image}
      end
      hash.each_value { |value| container_images_in(value, found) }
    elsif array = node.as_a?
      array.each { |value| container_images_in(value, found) }
    end
  end

  # Every rolling/rollback target the compatibility tests can request, paired
  # with the repository of the container's deployed image. A templated image
  # cannot be resolved here; the caller still needs to add it after rendering.
  def self.compatibility_images(config_path : String, deployment_dirs : Array(String)) : Array(String)
    return [] of String unless File.exists?(config_path)
    configured = CNFInstall::Config.parse_cnf_config_from_file(config_path).common.container_names
    return [] of String if configured.empty?

    images_by_container = {} of String => Set(String)
    deployment_dirs.uniq.each do |dir|
      next unless Dir.exists?(dir)
      yaml_files(dir) do |file|
        container_images_from_yaml(File.read(file)).each do |pair|
          images_by_container[pair[:name]] ||= Set(String).new
          images_by_container[pair[:name]] << pair[:image]
        end
      rescue ex
        Log.warn { "Could not read #{file} while collecting compatibility images: #{ex.message}" }
      end
    end

    targets = Set(String).new
    configured.each do |container|
      images_by_container[container.name]?.try &.each do |image|
        repository = ImageTag.repository_of(image)
        next if repository.empty?
        [container.rolling_update_test_tag,
         container.rolling_downgrade_test_tag,
         container.rolling_version_change_test_tag,
         container.rollback_from_tag].each do |tag|
          targets << "#{repository}:#{tag}" unless tag.empty?
        end
      end
    end
    targets.to_a.sort
  end

  # Suite-owned images plus every image declared in the Litmus operator and
  # fault manifests and in the given deployment directories. The caller loads
  # them into the cluster; the suite never pulls them from the internet in
  # offline mode.
  def self.collect_images(operator_path : String, deployment_dirs : Array(String) = [] of String, config_path : String? = nil) : Array(String)
    images = Set(String).new
    images << ClusterTools::IMAGE

    ([operator_path] + fault_manifests).each do |path|
      next unless File.exists?(path)
      images.concat(images_from_yaml(File.read(path)))
    end

    deployment_dirs.uniq.each do |dir|
      next unless Dir.exists?(dir)
      yaml_files(dir) do |file|
        images.concat(images_from_yaml(File.read(file)))
      rescue ex
        Log.warn { "Could not read #{file} while collecting images: #{ex.message}" }
      end
    end

    images.concat(compatibility_images(config_path, deployment_dirs)) if config_path
    images.to_a.sort
  end

  private def self.yaml_files(dir : String, &block : String ->) : Nil
    Dir.each_child(dir) do |entry|
      path = File.join(dir, entry)
      if File.directory?(path)
        next if entry.starts_with?(".") || SKIP_DIRS.includes?(entry)
        yaml_files(path, &block)
      elsif entry.ends_with?(".yml") || entry.ends_with?(".yaml")
        yield path
      end
    rescue ex
      Log.warn { "Could not scan #{path} for images: #{ex.message}" }
    end
  end

  # Copies the pinned Kyverno policies into the bundle. The CLI itself is a
  # normal download and is fetched by host_artifacts.
  def self.prepare_policies : String
    source = Kyverno.policies_repo_path
    unless ToolInstall.current?(Kyverno::POLICIES_BRANCH, source)
      unless Kyverno.download_policies_repo
        raise "could not download the Kyverno policies from github.com/kyverno/policies"
      end
    end

    destination = Offline.bundle_path("kyverno-policies")
    FileUtils.rm_rf(destination)
    FileUtils.cp_r(source, destination)
    destination
  end
end

desc "Download the host-side files an air-gapped run needs into the offline bundle"
task "airgap_prepare" do |_, args|
  if Offline.enabled?
    stdout_failure "airgap_prepare needs network access: unset #{Offline::MODE_ENV} and run it on a connected host."
    exit 1
  end

  StatusLine.push "Preparing the air-gap bundle in #{Offline.bundle_dir}..."
  failures = [] of String
  FileUtils.mkdir_p(Offline.downloads_dir)

  Airgap.host_artifacts.each do |url|
    destination = Offline.cache_path(url)
    if Offline.cached?(url)
      Log.info { "Already in the air-gap bundle: #{url}" }
      next
    end

    begin
      download_file(url, destination, headers: Airgap.headers_for(url))
      stdout_info "Fetched #{File.basename(destination)}"
    rescue ex
      failures << "#{url}: #{ex.message}"
    end
  end

  begin
    Airgap.prepare_policies
    stdout_info "Fetched the Kyverno policies"
  rescue ex
    failures << "Kyverno policies: #{ex.message}"
  end

  deployment_dirs = [] of String
  config_path = nil
  if configured = args.named["cnf-config"]?
    path = configured.to_s
    config_path = Dir.exists?(path) ? File.join(path, CONFIG_FILE) : path
    deployment_dirs << (Dir.exists?(path) ? path : File.dirname(path))
  end
  deployment_dirs << CNF_DIR if Dir.exists?(CNF_DIR)

  images = Airgap.collect_images(Offline.cache_path(LitmusManager::LITMUS_OPERATOR), deployment_dirs, config_path)
  File.write(Offline.images_file, images.join("\n") + "\n")
  stdout_info "Wrote #{images.size} image reference(s) to #{Offline.images_file}"

  StatusLine.pop
  if failures.empty?
    stdout_success "Air-gap bundle ready: #{Offline.bundle_dir}"
  else
    failures.each { |failure| stdout_failure "Could not prepare #{failure}" }
    stdout_failure "Air-gap bundle is incomplete: #{Offline.bundle_dir}"
    exit 1
  end
end

desc "Show what the offline bundle contains and what is missing"
task "airgap_status" do |_, args|
  stdout_info "Offline mode: #{Offline.enabled? ? "enabled" : "disabled"}"
  stdout_info "Bundle: #{Offline.bundle_dir}"

  missing = Airgap.host_artifacts.reject { |url| Offline.cached?(url) }
  stdout_info "Host artifacts: #{Airgap.host_artifacts.size - missing.size}/#{Airgap.host_artifacts.size} present"
  missing.each { |url| stdout_warning "Missing: #{url} -> #{Offline.cache_path(url)}" }

  policies = Offline.bundle_path("kyverno-policies")
  if Dir.exists?(policies)
    stdout_info "Kyverno policies: present"
  else
    stdout_warning "Missing: #{policies}"
  end

  if File.exists?(Offline.images_file)
    images = File.read_lines(Offline.images_file).reject(&.empty?)
    stdout_info "Images: #{images.size} listed in #{Offline.images_file}"
  else
    stdout_warning "Missing: #{Offline.images_file}"
  end
end
