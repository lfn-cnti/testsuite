require "http/client"

module Kyverno
  # renovate: datasource=github-releases depName=kyverno/kyverno
  VERSION = "1.19.0"
  # Branch of github.com/kyverno/policies the sample policies are taken from.
  POLICIES_BRANCH = "release-1.19"

  def self.cli_dir
    "#{tools_path}/kyverno-cli"
  end

  def self.binary_path
    "#{cli_dir}/kyverno"
  end

  # The CLI and the policies repo each carry a marker with the version they were
  # fetched at, so a suite built against a newer Kyverno replaces what an older
  # one left behind instead of silently reusing it.
  def self.install
    return true if installed?(cli_dir, ".kyverno_version", VERSION) &&
                   installed?(policies_repo_path, ".policies_version", POLICIES_BRANCH)

    FileUtils.rm_rf(cli_dir)
    FileUtils.mkdir_p(cli_dir)
    tempfile = File.tempfile("kyverno", ".tar.gz")
    download_file(download_url, tempfile.path)
    result = TarClient.untar(tempfile.path, cli_dir)
    tempfile.delete
    return false unless result[:status].success?
    File.write("#{cli_dir}/.kyverno_version", VERSION)

    download_policies_repo
  end

  def self.uninstall
    FileUtils.rm_rf(cli_dir)
    delete_policies_repo
    KubectlClient::Wait.resource_wait_for_uninstall("deployment", "kyverno",  namespace: "kyverno", wait_count: 180)
  end

  private def self.installed?(dir : String, marker : String, version : String) : Bool
    Dir.exists?(dir) && File.exists?("#{dir}/#{marker}") && File.read("#{dir}/#{marker}") == version
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

  def self.download_policies_repo
    delete_policies_repo
    url = "https://github.com/kyverno/policies.git"
    result = GitClient.clone("--depth 1 --branch #{POLICIES_BRANCH} #{url} #{policies_repo_path}")
    return false unless result[:status].success?
    File.write("#{policies_repo_path}/.policies_version", POLICIES_BRANCH)
    true
  end

  def self.delete_policies_repo
    FileUtils.rm_rf(policies_repo_path)
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

      def initialize(@message : String, @resources : Array(FailedResource))
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
      cmd = "#{Kyverno.binary_path} apply #{policy_path} --cluster --policy-report"
      ShellCmd.run("ls #{policy_path}", "kyverno_policy_path", force_output: true)
      result = ShellCmd.run(cmd, "Kyverno::PolicyAudit.run", force_output: true)
      policy_report = YAML.parse(report_document(result[:output]))

      failures = [] of PolicyFailure
      policy_report["results"].as_a.each do |test_result|
        if test_result["result"] == "fail"
          failed_resources = test_result["resources"].as_a.reduce([] of FailedResource) do |acc, resource|
            if exclude_namespaces.includes?(resource["namespace"])
              acc
            else
              acc << FailedResource.new(resource["kind"].to_s, resource["name"].to_s, resource["namespace"].to_s)
            end
          end

          if failed_resources.size > 0
            policy_failure = PolicyFailure.new(test_result["message"].to_s, failed_resources)
            failures.push(policy_failure)
          end
        end
      end

      failures
    end
  end

  def self.filter_failures_for_cnf_resources(resource_keys, failures)
    filtered = failures.map do |failure|
      failed_resources = failure.resources.select do |resource|
        CNFManager.resources_includes?(resource_keys, resource.kind, resource.name, resource.namespace)
      end
      PolicyAudit::PolicyFailure.new(failure.message, failed_resources)
    end
    filtered = filtered.select do |failure|
      failure.resources.size > 0
    end

    filtered
  end

end
