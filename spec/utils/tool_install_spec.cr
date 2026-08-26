require "../spec_helper"

# In-process, no network: the install block is a counter.
describe "ToolInstall" do
  it "installs once per version, reinstalls on a bump or force, and never marks a failed install", tags: ["points"] do
    dir = File.tempname("tool-install")
    FileUtils.mkdir_p(dir)
    artifact = File.join(dir, "tool")
    runs = 0
    install = ->(ok : Bool) { runs += 1; File.write(artifact, "bin") if ok; ok }

    ToolInstall.ensure("tool", "1.0", artifact) { install.call(true) }.should be_true
    runs.should eq(1)
    File.read(ToolInstall.marker(artifact)).should eq("1.0")

    # Same pin: no work.
    ToolInstall.ensure("tool", "1.0", artifact) { install.call(true) }.should be_true
    runs.should eq(1)

    # Bumped pin: reinstall.
    ToolInstall.ensure("tool", "1.1", artifact) { install.call(true) }.should be_true
    runs.should eq(2)
    ToolInstall.current?("1.1", artifact).should be_true
    ToolInstall.current?("1.0", artifact).should be_false

    # Force: reinstall even when current.
    ToolInstall.ensure("tool", "1.1", artifact, force: true) { install.call(true) }.should be_true
    runs.should eq(3)

    # A failed install leaves no marker, so the next run tries again.
    ToolInstall.ensure("tool", "1.2", artifact) { install.call(false) }.should be_false
    File.exists?(ToolInstall.marker(artifact)).should be_false
    ToolInstall.ensure("tool", "1.2", artifact) { install.call(true) }.should be_true
    runs.should eq(5)

    # A marker without its artifact is not "installed".
    File.delete(artifact)
    ToolInstall.current?("1.2", artifact).should be_false

    # forget drops the marker.
    ToolInstall.forget(artifact)
    File.exists?(ToolInstall.marker(artifact)).should be_false
  ensure
    FileUtils.rm_rf(dir.not_nil!)
  end
end
