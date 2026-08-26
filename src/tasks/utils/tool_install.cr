# Pinned tools are cached under tools_path across runs — and, on self-hosted
# CI runners, across jobs. A cached artifact carries a `<artifact>.version`
# marker holding the pin it was fetched at, so one rule serves every tool: an
# unchanged pin is a no-op, a bumped pin reinstalls, and a failed install
# leaves no marker behind to be mistaken for a good one.
module ToolInstall
  def self.marker(artifact : String) : String
    "#{artifact}.version"
  end

  # True when `artifact` exists and was installed at `version`.
  def self.current?(version : String, artifact : String) : Bool
    return false unless File.exists?(artifact)
    path = marker(artifact)
    File.exists?(path) && File.read(path).strip == version
  end

  # Installs `artifact` at `version` unless it is already current (or `force`
  # is set). The block performs the fetch and must leave `artifact` in place;
  # it returns whether it succeeded. The marker is written only after a
  # successful block and removed before the attempt, so an interrupted or
  # failed install is retried next time. Returns false only when the block ran
  # and failed.
  def self.ensure(name : String, version : String, artifact : String, force : Bool = false, & : -> Bool) : Bool
    logger = Log.for("ToolInstall")
    if !force && current?(version, artifact)
      logger.info { "#{name} #{version} is already installed: #{artifact}" }
      return true
    end
    File.delete?(marker(artifact))
    FileUtils.mkdir_p(File.dirname(artifact))
    logger.info { "Installing #{name} #{version}: #{artifact}" }
    return false unless yield
    File.write(marker(artifact), version)
    true
  end

  # Drops the marker with the artifact; for use by uninstall paths that remove
  # an artifact whose marker sits beside it rather than inside it.
  def self.forget(artifact : String)
    File.delete?(marker(artifact))
  end
end
