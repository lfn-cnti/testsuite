require "http/client"

module Kyverno
  # renovate: datasource=github-releases depName=kyverno/kyverno
  VERSION = "1.19.2"
  # Branch of github.com/kyverno/policies the sample policies are taken from.
  POLICIES_BRANCH = "release-1.19"

  # Raised when a Kyverno-based test cannot judge the CNF: the CLI or the
  # policies are not there, or the CLI printed no policy report. The task
  # runner reports the test as not run, with this reason (#2891).
  class AuditError < Exception; end

  # Why the last install did not complete, for AuditError.
  @@install_error : String? = nil

  def self.cli_dir
    "#{tools_path}/kyverno-cli"
  end

  def self.binary_path
    "#{cli_dir}/kyverno"
  end

  # Installs the CLI and the policies, or raises AuditError with the reason:
  # a test that went on without them would read no report (#2891).
  def self.install!
    @@install_error = nil
    return if install
    raise AuditError.new(@@install_error || "the Kyverno CLI #{VERSION} or its policies #{POLICIES_BRANCH} could not be installed")
  end

  def self.install
    cli = ToolInstall.ensure("kyverno CLI", VERSION, binary_path) do
      FileUtils.rm_rf(cli_dir)
      FileUtils.mkdir_p(cli_dir)
      tempfile = File.tempfile("kyverno", ".tar.gz")
      begin
        download_file(download_url, tempfile.path)
      rescue ex
        # download_file retries a transient failure, then raises.
        tempfile.delete
        @@install_error = "the Kyverno CLI #{VERSION} could not be downloaded from #{download_url}: #{ex.message.to_s.lines.first?.to_s.strip}"
        next false
      end
      result = TarClient.untar(tempfile.path, cli_dir)
      tempfile.delete
      @@install_error = "the Kyverno CLI #{VERSION} could not be unpacked" unless result[:status].success?
      result[:status].success?
    end
    return false unless cli

    ToolInstall.ensure("kyverno policies", POLICIES_BRANCH, policies_repo_path) do
      download_policies_repo
    end
  end

  # Cluster side only: the CLI and the policies checkout stay under the
  # suite home, versioned, until tools_purge.
  def self.uninstall
    KubectlClient::Wait.resource_wait_for_uninstall("deployment", "kyverno",  namespace: "kyverno", wait_count: 180)
  end

  def self.download_url
    # Support different flavours of Linux and MacOS
    flavour = ""
    {% if flag?(:linux) && flag?(:x86_64) %}
      flavour = "linux_x86_64"
    {% elsif flag?(:linux) && flag?(:aarch64) %}
      flavour = "linux_arm64"
    {% elsif flag?(:darwin) && flag?(:x86_64) %}
      flavour = "darwin_x86_64"
    {% elsif flag?(:darwin) && flag?(:aarch64) %}
      flavour = "darwin_arm64"
    {% end %}

    file_name = "kyverno-cli_v#{VERSION}_#{flavour}.tar.gz"
    "https://github.com/kyverno/kyverno/releases/download/v#{VERSION}/#{file_name}"
  end

  def self.best_practice_policy(policy_path : String) : String
    "#{policies_repo_path}/best-practices/#{policy_path}"
  end

  def self.policy_path(policy_path : String) : String
    "#{policies_repo_path}/#{policy_path}"
  end

  def self.custom_policy_path(policy_path : String) : String
    "#{tools_path}/custom-kyverno-policies/#{policy_path}"
  end

  def self.policies_repo_path
    "#{tools_path}/kyverno-policies"
  end

  # Clones the policies, retrying a failure that looks transient (a DNS or
  # network blip) as the suite's other downloads do.
  def self.download_policies_repo : Bool
    url = "https://github.com/kyverno/policies.git"
    NetRetry.with_retries("git clone #{url}") do
      delete_policies_repo
      result = GitClient.clone("--depth 1 --branch #{POLICIES_BRANCH} #{url} #{policies_repo_path}")
      unless result[:status].success?
        message = result[:error].to_s.strip
        raise NetRetry::TransientError.new(message) if NetRetry.transient?(Exception.new(message))
        @@install_error = "the Kyverno policies #{POLICIES_BRANCH} could not be cloned from #{url}: #{message.lines.last? || "git clone failed"}"
        return false
      end
    end
    true
  rescue ex : NetRetry::TransientError
    @@install_error = "the Kyverno policies #{POLICIES_BRANCH} could not be cloned from #{url}: #{ex.message.to_s.lines.last? || "git clone failed"}"
    false
  end

  def self.delete_policies_repo
    FileUtils.rm_rf(policies_repo_path)
    ToolInstall.forget(policies_repo_path)
  end

  module CustomPolicies
    class SELinuxEnabled
      ECR.def_to_s("src/templates/check-selinux-enabled.yaml")

      def policy_path
        custom_policies_path = "#{tools_path}/custom-kyverno-policies"
        file_path = "#{custom_policies_path}/check-selinux-enabled.yml"
        FileUtils.mkdir_p(custom_policies_path)
        File.write(file_path, self.to_s)
        file_path
      end
    end
  end

  module PolicyAudit
    struct FailedResource
      property kind
      property name
      property namespace

      def initialize(@kind : String, @name : String, @namespace : String)
      end
    end

    struct PolicyFailure
      property message
      property resources
      # Kyverno could not evaluate the policy for these resources (a report
      # result of `error`): filter_failures_for_cnf_resources raises for the
      # CNF's own, so a test does not pass on what Kyverno could not tell.
      property error : Bool

      def initialize(@message : String, @resources : Array(FailedResource), @error : Bool = false)
      end
    end

    # The report is the YAML document in the CLI output; older CLIs print a
    # few progress lines before it, so start at its `apiVersion:` line.
    private def self.report_document(output : String) : String
      lines = output.lines
      start = lines.index { |line| line.starts_with?("apiVersion:") } || 0
      lines[start..].join("\n")
    end

    def self.run(policy_path : String, exclude_namespaces : Array(String) = [] of String)
      raise AuditError.new("the Kyverno policy #{policy_path} is not there") unless File.exists?(policy_path)
      cmd = "#{Kyverno.binary_path} apply #{policy_path} --cluster --policy-report"
      result = ShellCmd.run(cmd, "Kyverno::PolicyAudit.run", force_output: true)
      failures_from(result[:output], exclude_namespaces, result[:status].exit_code, result[:error])
    end

    # The failures in the CLI's output. Kyverno 1.19 prints no report when no
    # rule matched a resource, and exits 0; it also exits 0 without a report
    # when it cannot reach the cluster, but then writes the client's errors
    # to stderr. So no report is no failures when stderr is clean and the exit
    # code 0, and an AuditError otherwise (#2891).
    def self.failures_from(output : String, exclude_namespaces : Array(String) = [] of String,
                           exit_code : Int32 = 0, stderr : String = "") : Array(PolicyFailure)
      unless output.lines.any?(&.starts_with?("apiVersion:"))
        problems = stderr.lines.map(&.strip).select { |line| line =~ /\A(E\d{4} |Error:|error:)/ }
        return [] of PolicyFailure if exit_code == 0 && problems.empty?
        said = (problems.empty? ? stderr.lines.map(&.strip).reject(&.empty?) : problems).last(3).join(" ")
        raise AuditError.new("kyverno apply printed no policy report (exit code #{exit_code})#{said.empty? ? "" : ": #{said[0, 300]}"}")
      end
      policy_report = YAML.parse(report_document(output))

      failures = [] of PolicyFailure
      (policy_report["results"]?.try(&.as_a?) || [] of YAML::Any).each do |test_result|
        outcome = test_result["result"]?.try(&.as_s?)
        next unless outcome == "fail" || outcome == "error"
        listed = test_result["resources"]?.try(&.as_a?) || [] of YAML::Any
        # An error that names no resource is the policy's own: it cannot be
        # narrowed to the CNF, and the audit did not run.
        if outcome == "error" && listed.empty?
          raise AuditError.new("Kyverno could not evaluate the policy: #{test_result["message"]?.to_s[0, 300]}")
        end
        resources = listed.compact_map do |resource|
          namespace = resource["namespace"]?.try(&.as_s?) || ""
          next if exclude_namespaces.includes?(namespace)
          FailedResource.new(resource["kind"]?.to_s, resource["name"]?.to_s, namespace)
        end
        next if resources.empty?
        failures.push(PolicyFailure.new(test_result["message"]?.to_s, resources, error: outcome == "error"))
      end

      failures
    end
  end

  # What a policy matched, read back from the live resource: Kyverno's report
  # names the resource and the rule, not the image, volume or securityContext
  # that tripped it. Each helper returns nothing (never raises) when the
  # resource cannot be read, so callers fall back to the policy message.
  module Findings
    def self.pod_spec(kind : String, name : String, namespace : String) : JSON::Any?
      resource = KubectlClient::Get.resource(kind, name, namespace)
      resource.dig?("spec", "template", "spec") || resource.dig?("spec")
    rescue
      nil
    end

    def self.containers(pod_spec : JSON::Any) : Array(JSON::Any)
      ["containers", "initContainers", "ephemeralContainers"].flat_map do |list|
        pod_spec.dig?(list).try(&.as_a?) || [] of JSON::Any
      end
    end

    # Containers whose image has no tag or the `latest` tag (a digest counts as pinned).
    def self.latest_tag_images(kind, name, namespace) : Array(NamedTuple(container: String, image: String))
      spec = pod_spec(kind, name, namespace) || return [] of NamedTuple(container: String, image: String)
      containers(spec).compact_map do |c|
        image = c.dig?("image").try(&.as_s?) || next
        next if image.includes?("@")
        tag = image.rpartition("/")[2].partition(":")[2]
        next unless tag.empty? || tag == "latest"
        {container: c.dig?("name").try(&.as_s?) || "", image: image}
      end
    end

    # hostPath volumes that mount a socket, with the containers mounting them.
    def self.socket_mounts(kind, name, namespace) : Array(NamedTuple(volume: String, path: String, containers: Array(String)))
      spec = pod_spec(kind, name, namespace) || return [] of NamedTuple(volume: String, path: String, containers: Array(String))
      (spec.dig?("volumes").try(&.as_a?) || [] of JSON::Any).compact_map do |v|
        path = v.dig?("hostPath", "path").try(&.as_s?) || next
        next unless path.ends_with?(".sock")
        volume = v.dig?("name").try(&.as_s?) || ""
        mounting = containers(spec).select do |c|
          (c.dig?("volumeMounts").try(&.as_a?) || [] of JSON::Any).any? { |m| m.dig?("name").try(&.as_s?) == volume }
        end.map { |c| c.dig?("name").try(&.as_s?) || "" }
        {volume: volume, path: path, containers: mounting}
      end
    end

    # seLinuxOptions set at pod level ("pod") or on a container, rendered as k=v.
    def self.selinux_options(kind, name, namespace) : Array(NamedTuple(scope: String, options: String))
      spec = pod_spec(kind, name, namespace) || return [] of NamedTuple(scope: String, options: String)
      found = [] of NamedTuple(scope: String, options: String)
      render = ->(o : JSON::Any) { o.as_h.map { |k, v| "#{k}=#{v}" }.join(", ") }
      if o = spec.dig?("securityContext", "seLinuxOptions")
        found << {scope: "pod", options: render.call(o)}
      end
      containers(spec).each do |c|
        if o = c.dig?("securityContext", "seLinuxOptions")
          found << {scope: c.dig?("name").try(&.as_s?) || "", options: render.call(o)}
        end
      end
      found
    end
  end

  # The failures on the CNF's own resources. An evaluation error on one of
  # them raises AuditError: the test does not pass on what Kyverno could not
  # tell. Errors on the cluster's other resources are not the CNF's.
  def self.filter_failures_for_cnf_resources(resource_keys, failures)
    filtered = failures.map do |failure|
      failed_resources = failure.resources.select do |resource|
        CNFManager.resources_includes?(resource_keys, resource.kind, resource.name, resource.namespace)
      end
      PolicyAudit::PolicyFailure.new(failure.message, failed_resources, failure.error)
    end
    filtered = filtered.select do |failure|
      failure.resources.size > 0
    end

    errors = filtered.select(&.error).map do |failure|
      names = failure.resources.map { |r| "#{r.kind}/#{r.name}#{r.namespace.empty? ? "" : " in #{r.namespace}"}" }
      "#{names.join(", ")}: #{failure.message}"
    end
    raise AuditError.new("Kyverno could not evaluate the policy for #{errors.first(3).join("; ")[0, 400]}#{errors.size > 3 ? " (#{errors.size} in all)" : ""}") unless errors.empty?

    filtered.reject(&.error)
  end

end
