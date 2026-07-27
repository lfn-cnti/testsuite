require "halite"
require "http/client"
require "log"
require "mime"
require "uri"


ROOT_URL = "https://api.github.com/repos"

module ReleaseManager 
  module CompileTimeVersionGenerater
    macro tagged_version
      {% current_branch = `git rev-parse --abbrev-ref HEAD`.split("\n")[0].strip %}
      {% current_hash = `git rev-parse --short HEAD` %}
      {% current_status = `git status`.split("\n")[0].strip %}
      {% current_tag = (!`git tag --points-at HEAD`.empty? && `git tag --points-at HEAD`.split("\n")[-2].strip) || `git tag --points-at HEAD` %} 
      {% puts "current_branch during compile: #{current_branch}" %}
      {% puts "current_tag during compile: #{current_tag}" %}
      {% if current_tag.strip == "" %}
        VERSION = {{current_branch}} + "-#{Time.local.to_s("%Y-%m-%d-%H%M%S")}-{{current_hash.strip}}"
      {% else %}
        VERSION = {{current_tag.strip}}
      {% end %}
    end
  end
  
  CompileTimeVersionGenerater.tagged_version

  class GithubReleaseManager
    def initialize(repo_name : String)
      @repo_name = repo_name
    end

    def repo_url
      "#{ROOT_URL}/#{@repo_name}"
    end

    def github_releases : Array(JSON::Any)
      existing_releases = Halite.auth("Bearer #{ENV["GITHUB_TOKEN"]}").
        get(
          "#{self.repo_url}/releases",
          headers: {Accept: "application/vnd.github.v3+json"}
        )
      JSON.parse(existing_releases.body).as_a
    end 

    def remote_main_branch_hash
      results =  `git ls-remote https://github.com/#{@repo_name}.git main | awk '{ print $1}' | cut -c1-7`.strip
      Log.info {"remote_main_branch_hash: #{results}"}
      results.strip("\n")
    end

    def upsert_release(version=nil) : Tuple((JSON::Any | Nil), (JSON::Any | Nil))
      Log.info {"upsert_release"}
      found_release : (JSON::Any | Nil) = nil
      asset : (JSON::Any | Nil) = nil
      Log.info {"version: #{version}"}
      upsert_version = (version || ReleaseManager::VERSION)
      Log.info {"upsert_version: #{upsert_version}"}
      # cnf_bin_path = "cnf-testsuite"
      # cnf_bin_asset_name = "#{cnf_bin_path}"
      cnf_bin_asset_name = "cnf-testsuite"

      if self.remote_main_branch_hash == ReleaseManager.current_hash
        upsert_version = upsert_version.sub("HEAD", "main")
      end
      if upsert_version =~ /(?i)(main)/
        prerelease = true
        draft = false
      else
        prerelease = false
        draft = false
      end
      Log.info {"upsert_version: #{upsert_version}"}
      Log.info {"upsert_version comparison: upsert_version =~ /(?i)(main|v[0-9]|test_version)/ : #{upsert_version =~ /(?i)(main|v[0-9]|test_version)/}"}
      #master-381d20d
      invalid_version = !(upsert_version =~ /(?i)(main|v[0-9]|test_version)/)
      snap_shot_version = (upsert_version =~ /(?i)(main-)/)
      head = (ReleaseManager.current_branch == "HEAD")
      skip_snapshot_detached_head = (head && snap_shot_version)
      Log.info {"invalid_version: #{invalid_version}"}
      Log.info {"current_branch: #{ReleaseManager.current_branch}"}
      Log.info {"skip_snapshot_detached_head: #{skip_snapshot_detached_head}"}
      if skip_snapshot_detached_head || invalid_version
        Log.info {"Not creating a release for : #{upsert_version}"}
        return {found_release, asset} 
      end

      # NOTE: build MUST be done first so we can sha256sum for release notes
      # Build a static binary so it will be portable on other machines in non test
      unless ENV["CRYSTAL_ENV"]? == "TEST"
        # Rely on the docker ci to create the static binary
        # rm_resp = `rm ./cnf-testsuite`
        # Log.info {"rm_resp: #{rm_resp}"}
        # Log.info {"building static binary"}
        # build_resp = `crystal build src/cnf-testsuite.cr --release --static --link-flags "-lxml2 -llzma"`
        # Log.info {"build_resp: #{build_resp}"}
        # the name of the binary asset must be unique across all releases in github for project
        # TODO if upsert version == test then make unique
        cnf_tarball_name = "cnf-testsuite-#{upsert_version}.tar.gz"
        cnf_tarball = `tar -czvf #{cnf_tarball_name} ./#{cnf_bin_asset_name}`
        Log.info {"cnf_tarball: #{cnf_tarball}"}
        # cnf_bin_asset_name = "#{cnf_bin_path}-static" # change upload name for static builds
        cnf_bin_asset_name = "#{cnf_tarball_name}" # change upload name for static builds
      end
      Log.info {"upsert_version: #{upsert_version}"}
      release_resp = self.github_releases
      Log.info {"release_resp size: #{release_resp.size}"}

      found_release = release_resp.find {|x| x["tag_name"] == upsert_version} 
      Log.info {"find found_release?: #{found_release}"}

      release_url = "#{self.repo_url}/releases"
      unless found_release
        headers = {Accept: "application/vnd.github.v3+json"}
        json = { "tag_name" => upsert_version,
                 "draft" => draft,
                 "prerelease" => prerelease,
                 "name" => "#{upsert_version} #{Time.local.to_s("%B %d, %Y")}",
                 "generate_release_notes" => true }

        Log.info {"Release not found.  Creating a release: # url: #{release_url} headers: #{headers} json #{json}"}

        found_resp = Halite.auth("Bearer #{ENV["GITHUB_TOKEN"]}").post(release_url, headers: headers, json: json)
        found_release = JSON.parse(found_resp.body)
        # TODO error if cant create a release
        Log.info {"(unless) found_release: #{found_release}"}
      end

      # PATCH /repos/:owner/:repo/releases/:release_id
      found_resp = Halite.auth("Bearer #{ENV["GITHUB_TOKEN"]}").
        patch("#{release_url}/#{found_release["id"]}",
              json: { "tag_name" => upsert_version,
                      "draft" => draft,
                      "prerelease" => prerelease,
                      "name" => "#{upsert_version} #{Time.local.to_s("%B %d, %Y")}",
                      "generate_release_notes" => true })
      found_release = JSON.parse(found_resp.body)

      Log.info {"found_release (after create): #{found_release}"}

      upload_url = found_release["upload_url"]?.try(&.as_s) || 
      raise "Release payload is missing 'upload_url'. Response was: #{found_release}"
    
      Log.info {"uploading binary"}
      asset = ReleaseManager.upload_release_asset(upload_url, cnf_bin_asset_name)
      {found_release, asset}
    end

    def delete_release(version)
      # DELETE /repos/:owner/:repo/releases/assets/:asset_id
      # DELETE /repos/:owner/:repo/releases/:release_id
      release_resp = self.github_releases
      puts "this is the version #{version}"
      found_release = release_resp.find {|x| x["tag_name"] == "#{version}"} 
      puts "this is found_release #{typeof(found_release)}"
      if found_release
        puts "this is found_release id #{found_release["id"]}"
        resp = Halite.auth("Bearer #{ENV["GITHUB_TOKEN"]}").
          delete("#{self.repo_url}/releases/#{found_release["id"]}")
        resp_code = resp.status_code
        Log.info {"resp_code: #{resp_code}"}
      else 
        resp_code = 404
      end 
      resp_code
    end 


  end

  def self.tag(options="")
    results = `git tag #{options}`
    Log.info {"git tag: #{results}"}
    results.split("\n")
  end

  def self.current_tag
    ReleaseManager.tag("--points-at HEAD")
  end

  def self.current_branch
    results = `git rev-parse --abbrev-ref HEAD`.split("\n")[0].strip
    Log.info {"current_branch rev-parse: #{results}"}
    results.strip("\n")
  end

  def self.current_hash
    results = `git rev-parse --short HEAD`
    Log.info {"current_hash rev-parse: #{results}"}
    results.strip("\n")
  end

  def self.upload_release_asset(upload_url : String, asset_name : String)
    # TODO Add test that checks for uploaded corrupted binary.
    base_name = File.basename(asset_name)
    query_params = URI::Params.encode({"name" => base_name})
    formatted_upload_url = "#{upload_url.split('{').first}?#{query_params}"
    mime_type = MIME.from_filename(asset_name, "application/octet-stream")

    headers = HTTP::Headers{
      "Authorization"  => "Bearer #{ENV["GITHUB_TOKEN"]}",
      "Content-Type"   => mime_type,
      "Content-Length" => File.size(asset_name).to_s,
    }

    response = File.open(asset_name) do |file|
      HTTP::Client.post(formatted_upload_url, headers: headers, body: file)
    end

    if response.status_code == 422 && response.body.includes?("already_exists")
      Log.info { "Asset #{base_name} already exists on release, skipping upload." }
      return JSON.parse(response.body)
    end

    unless response.success?
      truncated_body = response.body[0, 512]
      raise "Asset upload failed: #{response.status_code} - #{truncated_body}"
    end

    asset = JSON.parse(response.body)
    Log.info {"asset: #{asset}"}
    asset
  end

end 
