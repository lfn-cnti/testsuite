require "../spec_helper.cr"

# TODO: fix spec tests for release manager
# Issues:
# - after moving release-manager to the testsuite, using cnf-testsuite/release manager repo does not work correctly anymore
# - it cannot be safely changed to the main testsuite repo as it would create testing mess there
# - body of "ReleseManager" spec test is executed along with any other spec test execution
#
#describe "ReleaseManager" do
#  ghrm = ReleaseManager::GithubReleaseManager.new("cnf-testsuite/release_manager")
#  
#  # upsert a test release
#  unless ENV["GITHUB_TOKEN"]?.nil?
#    ghrm.upsert_release
#  end
#
#  after_all do
#    unless ENV["GITHUB_TOKEN"]?.nil?
#      ghrm.delete_release("test_version")
#    end
#  end
#  it "'#ReleaseManager.tag' should return the list of tags on the current branch", tags:["release_manager"] do
#    (ReleaseManager.tag.size).should be > 0
#  end
#  it "'#ReleaseManager.tag' should accept a list of options", tags:["release_manager"] do
#      (ReleaseManager.tag("--list")).should_not eq([""])
#      (ReleaseManager.tag("--list 'shouldbeempty'")).should eq([""]) 
#  end
#  it "'#ReleaseManager.current_branch' should return the current branch as a string", tags:["release_manager"] do
#    if ReleaseManager.on_a_tag?
#      (ReleaseManager.tag("--list")).should_not eq([""])
#    else
#      (ReleaseManager.current_branch).should_not eq("")
#    end
#  end
#
#  it "'#ReleaseManager.current_hash' should return the current hash as a string", tags:["release_manager"] do
#    (ReleaseManager.current_hash).should_not eq("")
#  end
#
#  it "'#ReleaseManager::GithubReleaseManager.remote_main_branch_hash' should return the current hash as a string", tags:["release_manager"] do
#    (ghrm.remote_main_branch_hash).should_not eq("")
#  end
#
#  it "'#ReleaseManager::GithubReleaseManager.github_releases' should return the existing releases", tags:["release_manager"] do
#    if ENV["GITHUB_TOKEN"]?.nil?
#      puts "Warning: Set GITHUB_TOKEN to activate release manager tests!".colorize(:red)
#    else 
#      ((ghrm.github_releases.size) > 0).should be_true
#    end
#  end
#
#  it "'#ReleaseManager::GithubReleaseManager.upsert_release' should return the upserted release and asset response", tags:["release_manager"] do
#    if ENV["GITHUB_TOKEN"]?.nil?
#      puts "Warning: Set GITHUB_TOKEN to activate release manager tests!".colorize(:red)
#    else 
#      found_release, asset = ghrm.upsert_release("test_version")
#      if asset
#        (asset["errors"]?==nil || (asset["errors"]? && asset["errors"][0]["code"]  == "already_exists")).should be_truthy
#      else
#        (asset).should_not be_nil
#      end
#    end
#  end
#
#  it "'#ReleaseManager::GithubReleaseManager.upsert_release' should return nil if not on a valid version", tags:["release_manager"] do
#    found_release, asset = ghrm.upsert_release("invalid_version")
#    (asset).should be_nil
#  end
#
#  it "'#ghrm.delete_release' should delete the release from the found_id", tags:["release_manager"] do
#    if ENV["GITHUB_TOKEN"]?.nil?
#      puts "Warning: Set GITHUB_TOKEN to activate release manager tests!".colorize(:red)
#    else 
#      found_release, asset = ghrm.upsert_release("test_version")
#      # wait for upsert to finish
#      Log.info {"upsert sleep"}
#      sleep 10.0
#      resp_code = ghrm.delete_release("test_version")
#      resp_code.should eq 204
#    end
#  end
#  it "'#ReleaseManager.detached_head?' should return if the head is detached", tags:["release_manager"] do
#    (ReleaseManager.detached_head?).should_not be_nil
#  end
#
#  it "'#ReleaseManager.commit_message_issues' should list previsions releases", tags:["release_manager"] do
#    hash = ReleaseManager.current_hash
#    #todo dynamically change issues tag so that it is only a few weeks back
#    # if this tag is too far in the past, the specs will not run
#    issues = ReleaseManager.commit_message_issues("v0.0.1-rm", hash)
#    (issues[0].match(/#/)).should_not be_nil
#  end
#
#  it "'#ReleaseManager.latest_release' should return latest release", tags:["release_manager"] do
#    if ENV["GITHUB_TOKEN"]?.nil?
#      puts "Warning: Set GITHUB_TOKEN to activate release manager tests!".colorize(:red)
#    else 
#      release = ghrm.latest_release
#      # https://github.com/semver/semver/blob/master/semver.md#is-v123-a-semantic-version
#      (release.match(/^(.|)(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/)).should_not be_nil
#    end
#  end
#
#  it "'#ReleaseManager.latest_snapshot' should return the latest snapshot", tags:["release_manager"] do
#    if ENV["GITHUB_TOKEN"]?.nil?
#      puts "Warning: Set GITHUB_TOKEN to activate release manager tests!".colorize(:red)
#    else 
#      snapshot = ghrm.latest_snapshot
#      # https://github.com/semver/semver/blob/master/semver.md#is-v123-a-semantic-version
#      (snapshot.match(/(?i)(main)/)).should_not be_nil
#    end
#  end
#
#
#  it "'#ReleaseManager.issue_title' should return issue title", tags:["release_manager"] do
#    if ENV["GITHUB_TOKEN"]?.nil?
#      puts "Warning: Set GITHUB_TOKEN to activate release manager tests!".colorize(:red)
#    else 
#      title = ghrm.issue_title("#1")
#      (title.match(/test issue/)).should_not be_nil
#    end
#  end
#
#end
