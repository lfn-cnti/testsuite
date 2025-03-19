require "../spec_helper.cr"

describe "Git" do
  it "'installation_found?' should show a git client was located", tags:["git"] do
    (GitClient.installation_found?).should be_true
  end

  it "'git_global_response()' should return the information about the git installation", tags:["git"] do
    (git_global_response(true)).should contain("git version")
  end

  it "'git_local_response()' should return the information about the git installation", tags:["git"] do
    (git_local_response(true)).should eq("") 
  end

  it "'git_version()' should return the information about the git version", tags:["git"] do
    (git_version(git_global_response)).should match(/(([0-9]{1,3}[\.]){1,2}[0-9]{1,3})/)
    (git_version(git_local_response)).should contain("")
  end

  it "'git_installations()' should return the information about the git installation", tags:["git"] do
    (git_installation(true)).should contain("git found")
  end
end
