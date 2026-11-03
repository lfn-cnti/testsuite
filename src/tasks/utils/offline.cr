require "digest/sha256"
require "file_utils"
require "log"
require "uri"

# Air-gap support. Every external host-side fetch goes through download_file,
# so an offline run resolves those fetches from a bundle prepared on a
# connected host instead of reaching the internet.
module Offline
  MODE_ENV = "CNTI_TESTSUITE_OFFLINE"
  DIR_ENV  = "CNTI_TESTSUITE_OFFLINE_DIR"

  # The download in the bundle is named after its URL, not just its basename:
  # one source URL is fetched to different output paths (a Litmus fault is
  # downloaded once per target workload), and two URLs can share a basename.
  class MissingArtifactError < Exception
  end

  def self.enabled? : Bool
    case ENV[MODE_ENV]?.try(&.strip.downcase)
    when "1", "true", "yes", "on"
      true
    else
      false
    end
  end

  def self.bundle_dir : String
    configured = ENV[DIR_ENV]?.try(&.strip)
    return configured if configured && !configured.empty?
    File.join(testsuite_resources_dir, "airgap")
  end

  def self.bundle_path(*parts : String) : String
    File.join([bundle_dir] + parts.to_a)
  end

  def self.downloads_dir : String
    bundle_path("downloads")
  end

  def self.images_file : String
    bundle_path("images.txt")
  end

  def self.cache_path(url : String) : String
    name = File.basename(URI.parse(url).path)
    name = "download" if name.empty?
    digest = Digest::SHA256.hexdigest(url)[0, 16]
    File.join(downloads_dir, "#{digest}-#{name}")
  end

  def self.cached?(url : String) : Bool
    path = cache_path(url)
    File.exists?(path) && File.size(path) > 0
  end

  # Copies the bundle's copy of `url` to output_path. Raises when the bundle
  # does not have it, naming both the URL and the directory to add it to.
  def self.fetch_cached(url : String, output_path : String) : Bool
    source = cache_path(url)
    diagnostic_url = url_without_credentials(url)
    unless cached?(url)
      raise MissingArtifactError.new(
        "Offline mode: #{diagnostic_url} is not in the air-gap bundle at #{bundle_dir}. " \
        "Run `cnti-testsuite airgap_prepare` on a connected host, or copy the file to #{source}."
      )
    end

    FileUtils.mkdir_p(File.dirname(output_path))
    unless same_path?(source, output_path)
      FileUtils.cp(source, output_path)
    end
    Log.info { "Offline mode: resolved #{diagnostic_url} from #{source}" }
    true
  end

  # Copies an existing file into the bundle's cache. airgap_prepare downloads
  # straight into the cache so an interrupted preparation keeps every artifact
  # it already fetched; this is the way to seed a bundle by hand (and in specs).
  def self.store(url : String, source : String) : String
    destination = cache_path(url)
    return destination if same_path?(destination, source)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(source, destination)
    destination
  end

  private def self.same_path?(first : String, second : String) : Bool
    File.expand_path(first) == File.expand_path(second)
  end
end
