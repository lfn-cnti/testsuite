# A chart installed from a Helm repository or an OCI registry has releases
# before the one under test. The rollout tests move such a release between
# the installed chart version and the one before it with `helm upgrade`,
# image and pod spec together, as an upgrade does; changing only an image
# under the current chart's spec tests version skew instead, which no
# upgrade ever produces (#2820).
module ReleaseUpgrade
  Log = ::Log.for("ReleaseUpgrade")
  alias Ref = Tuple(String, String, String)
  ROLLOUT_KINDS = ["deployment", "statefulset", "daemonset"]
  ROLLOUT_TIMEOUT = "200s"

  class Release
    getter config : CNFInstall::ConfigV2::HelmChartConfig
    getter common : CNFInstall::ConfigV2::CommonParameters
    getter namespace : String
    getter workloads : Array(Ref)
    getter installed : String
    getter app_version : String?
    # The release is at a version other than the installed one.
    property moved = false

    def initialize(@config, @common, @namespace, @workloads, @installed, @app_version)
    end

    def name : String
      config.name
    end

    def chart_name : String
      config.helm_chart_name
    end

    def oci? : Bool
      !config.registry_url.empty?
    end

    def label : String
      "chart #{name} (#{chart_name} #{installed})"
    end
  end

  # The releases the CNF installed from a repository or a registry, each with
  # the workloads the composite manifest attributes to it. A chart whose
  # release is not in the cluster is left out.
  def self.releases(config) : Array(Release)
    config.deployments.helm_charts.compact_map do |chart|
      namespace = chart.namespace.empty? ? DEFAULT_CNF_NAMESPACE : chart.namespace
      status = Helm.release_status(chart.name, namespace)
      unless status
        Log.warn { "chart #{chart.name}: no release in #{namespace}, not moved" }
        next nil
      end
      installed = (status["chart"]?.try(&.as_s?) || "").sub(/\A#{Regex.escape(chart.helm_chart_name)}-/, "")
      Release.new(chart, config.common, namespace, workloads_of(chart.name, namespace), installed, status["app_version"]?.try(&.as_s?))
    end
  end

  # Kind, name and namespace of the workloads a rollout can be waited for
  # (Deployments, StatefulSets, DaemonSets) that the installed manifest
  # attributes to the deployment.
  def self.workloads_of(deployment_name : String, namespace : String) : Array(Ref)
    refs = [] of Ref
    return refs unless File.exists?(COMMON_MANIFEST_FILE_PATH)
    File.read(COMMON_MANIFEST_FILE_PATH).split(/^---\n/m).each do |doc|
      next unless doc =~ /\A# Source: helm_chart:#{Regex.escape(deployment_name)} \(/
      yml = begin
        YAML.parse(doc)
      rescue YAML::ParseException
        nil
      end
      next unless yml
      kind = yml.dig?("kind").try(&.as_s?) || next
      next unless ROLLOUT_KINDS.includes?(kind.downcase)
      name = yml.dig?("metadata", "name").try(&.as_s?) || next
      refs << {kind, name, yml.dig?("metadata", "namespace").try(&.as_s?) || namespace}
    end
    refs
  end

  # The version to move the release to, or nil with the reason on the result:
  # the configured previous_chart_version, else the release before the
  # installed one in the repository, the closest older version of the same
  # form. A chart version that ships the same app version as the installed
  # one is a chart-only change that rolls no image, so the search goes on to
  # the closest older version with another app version; when every older
  # version ships the installed app version, the release is not judged. When
  # the repository does not say (an OCI registry lists tags only), the
  # closest older version is taken.
  def self.previous_version(release : Release, result) : String?
    configured = release.config.previous_chart_version
    unless configured.empty?
      if configured == release.installed
        result.append_remediation("previous_chart_version #{configured} for chart #{release.name} is the installed version, so nothing would change: set it to an older released version")
        return nil
      end
      # A newer version would turn the downgrade into an upgrade and the
      # upgrade into a downgrade.
      if ImageTag.older?(configured, release.installed) == false
        result.append_remediation("previous_chart_version #{configured} for chart #{release.name} is not older than the installed version #{release.installed}: set it to an older released version")
        return nil
      end
      return configured
    end
    versions = repository_versions(release)
    unless versions
      result.append_remediation("No previous_chart_version configured for chart #{release.name}, and the versions of #{release.chart_name} in its #{release.oci? ? "registry" : "repository"} could not be listed: set previous_chart_version to the release before #{release.installed}")
      return nil
    end
    all = versions.map(&.[:version])
    previous = ImageTag.previous_release(release.installed, all)
    unless previous
      result.append_remediation("No previous_chart_version configured for chart #{release.name}, and no release before #{release.installed} is listed for #{release.chart_name}: set previous_chart_version to an older released version")
      return nil
    end
    # Back through the listing, already fetched, until a version ships
    # another app version (or the repository does not say).
    same_app = [] of String
    candidate = previous
    while candidate
      app = versions.find { |v| v[:version] == candidate }.try(&.[:app_version])
      break unless app && release.app_version && app == release.app_version
      same_app << candidate
      candidate = ImageTag.previous_release(candidate, all)
    end
    unless candidate
      result.append_remediation("No previous_chart_version configured for chart #{release.name}, and every release before #{release.installed} listed for #{release.chart_name} ships the same app version #{release.app_version}, so moving to one rolls no image: set previous_chart_version to a version with another app version")
      return nil
    end
    chosen = candidate
    note = same_app.empty? ? "" : " (#{same_app.join(", ")} ship#{same_app.size == 1 ? "s" : ""} the same app version #{release.app_version} as the installed chart)"
    result.append_description("#{release.label}: no previous_chart_version configured, using #{chosen}, the release before#{note}")
    chosen
  end

  def self.repository_versions(release : Release) : Array(Helm::ChartVersion)?
    cfg = release.config
    if release.oci?
      tags = ClusterTools.image_tags(cfg.registry_url.sub(/\Aoci:\/\//, ""), plain_http: cfg.plain_http)
      tags.try(&.map { |t| {version: t, app_version: nil.as(String?)} })
    else
      Helm.repo_update(cfg.helm_repo_name) unless cfg.helm_repo_url.empty?
      Helm.chart_versions(cfg.helm_repo_name, cfg.helm_chart_name)
    end
  end

  # Moves the release to the chart at `version` with the configured values
  # and waits for every workload's rollout. Nil when it completed; otherwise
  # why not, with each workload that did not roll out as an impacted resource
  # when `judged`.
  def self.move(release : Release, version : String, result, test_name : String, judged : Bool) : String?
    Log.info { "#{release.label}: moving to #{version}" }
    chart_path = chart_path(release, version)
    RunStop.register(stop_key(release)) { set_back(release) }
    # Moved until helm says otherwise: a move back that fails leaves the
    # release where it was, and restore must still bring it back.
    release.moved = true
    values = release.config.helm_values.empty? ? nil : CNFInstall.resolve_helm_values(release.config.helm_values, CNFInstall.installed_config_dir)
    Helm.upgrade(release.name, chart_path, namespace: release.namespace, values: values)
    release.moved = version != release.installed
    wait(release, result, "#{release.label} during the #{test_name} to #{version}", "upgrade to chart version #{version}", judged)
  rescue ex : Helm::ShellCMD::HelmCMDException
    reason = "helm: #{ex.message.to_s.lines.map(&.strip).reject(&.empty?).first?}"
    result.add_impacted_resource("HelmRelease", release.name, release.namespace, reason: "#{test_name} to chart version #{version} failed: #{reason}") if judged
    reason
  end

  # `helm rollback` to the previous revision, judged.
  def self.rollback(release : Release, result, test_name : String) : String?
    Log.info { "#{release.label}: rolling back to the previous revision" }
    Helm.rollback(release.name, release.namespace)
    release.moved = current_version(release) != release.installed
    wait(release, result, "#{release.label} during the #{test_name}", "rollback to the previous revision", true)
  rescue ex : Helm::ShellCMD::HelmCMDException
    reason = "helm: #{ex.message.to_s.lines.map(&.strip).reject(&.empty?).first?}"
    result.add_impacted_resource("HelmRelease", release.name, release.namespace, reason: "helm rollback failed: #{reason}")
    reason
  end

  # Every moved release back at its installed version, whatever happened,
  # so the tests after this one start from the CNF as deployed. A release
  # that does not come back is a finding of the test.
  def self.restore(releases : Array(Release), result, test_name : String) : Bool
    all_back = true
    releases.each do |release|
      if release.moved
        reason = move(release, release.installed, result, "restore after #{test_name}", false)
        if reason
          result.add_impacted_resource("HelmRelease", release.name, release.namespace, reason: "not back at chart version #{release.installed} after #{test_name}: #{reason}")
          all_back = false
        end
      end
      # A release still moved keeps its stop hook: a stop puts it back.
      RunStop.done(stop_key(release)) unless release.moved
    end
    all_back
  end

  def self.stop_key(release : Release) : String
    "move release #{release.name} in #{release.namespace} back to chart version #{release.installed}"
  end

  # What a stop runs while the release is moved: back to the installed chart,
  # without waiting for the rollout.
  def self.set_back(release : Release) : Nil
    values = release.config.helm_values.empty? ? nil : CNFInstall.resolve_helm_values(release.config.helm_values, CNFInstall.installed_config_dir)
    Helm.upgrade(release.name, chart_path(release, release.installed), namespace: release.namespace, values: values)
    nil
  rescue Helm::ShellCMD::HelmCMDException
    nil
  end

  def self.current_version(release : Release) : String?
    Helm.release_status(release.name, release.namespace).try { |s| (s["chart"]?.try(&.as_s?) || "").sub(/\A#{Regex.escape(release.chart_name)}-/, "") }
  end

  # The chart directory of `version`: the install's own pull for the installed
  # version, else pulled next to it (once per version).
  def self.chart_path(release : Release, version : String) : String
    installed_path = File.join(DEPLOYMENTS_DIR, release.name, release.chart_name)
    return installed_path if version == release.installed && Dir.exists?(installed_path)
    destination = File.join(DEPLOYMENTS_DIR, "#{release.name}-#{version}")
    path = File.join(destination, release.chart_name)
    return path if Dir.exists?(path)
    FileUtils.mkdir_p(destination)
    cfg = release.config
    if release.oci?
      tls = cfg.tls_profile.empty? ? nil : release.common.tls_profiles[cfg.tls_profile]?
      Helm.pull_oci(cfg.registry_url, version: version, destination: destination, untar: true,
        ca_file: tls.try(&.ca_file), cert_file: tls.try(&.cert_file), key_file: tls.try(&.key_file),
        insecure_skip_tls_verify: cfg.skip_tls_verify, plain_http: cfg.plain_http)
    else
      Helm.pull(cfg.helm_repo_name, cfg.helm_chart_name, version: version, destination: destination, untar: true)
    end
    path
  end

  # Waits for every workload of the release; the reasons of those that did
  # not roll out, each reported when judged. Nil when all did.
  def self.wait(release : Release, result, heading : String, step : String, judged : Bool) : String?
    reasons = [] of String
    release.workloads.each do |(kind, name, namespace)|
      error = nil
      ok = begin
        KubectlClient::Rollout.status(kind, name, namespace: namespace, timeout: ROLLOUT_TIMEOUT)
      rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
        error = ex.message.to_s.lines.first?
        false
      end
      next if ok
      why = judged ? WorkloadDiagnostics.report(result, kind, name, namespace, "#{kind}/#{name} in #{heading}") : WorkloadDiagnostics.problems(kind, name, namespace)
      reason = "#{kind}/#{name} in #{namespace}: rollout did not complete within #{ROLLOUT_TIMEOUT} after the #{step}#{error ? ": #{error}" : ""}#{why.first?.try { |w| "; #{w}" }}"
      result.add_impacted_resource(kind, name, namespace, reason: "rollout did not complete within #{ROLLOUT_TIMEOUT} after the #{step}#{error ? ": #{error}" : ""}#{why.first?.try { |w| "; #{w}" }}") if judged
      reasons << reason
    end
    reasons.empty? ? nil : reasons.join("; ")
  end
end
