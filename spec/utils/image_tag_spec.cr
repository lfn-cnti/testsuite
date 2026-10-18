require "../spec_helper"
require "../../src/tasks/utils/image_tag.cr"

describe "ImageTag" do
  it "takes the tag from a reference, not the registry port", tags: ["versioned_tag"] do
    ImageTag.tag_of("coredns/coredns:1.11.3").should eq "1.11.3"
    ImageTag.tag_of("registry.example:5000/org/app:v2").should eq "v2"
    ImageTag.tag_of("registry.example:5000/org/app").should be_nil
    ImageTag.tag_of("org/app:1.0@sha256:abc").should eq "1.0"
  end

  it "accepts digests and version-like tags, rejects latest, untagged and moving tags", tags: ["versioned_tag"] do
    ImageTag.unversioned_reason("org/app@sha256:0123abcd").should be_nil
    ImageTag.unversioned_reason("org/app:1.2.3").should be_nil
    ImageTag.unversioned_reason("org/app:v2").should be_nil
    ImageTag.unversioned_reason("bitnamilegacy/wordpress:6.0.2-debian-11-r0").should be_nil
    ImageTag.unversioned_reason("org/app:latest").should eq "uses the latest tag"
    ImageTag.unversioned_reason("org/app").should eq "has no tag (implicitly latest)"
    ImageTag.unversioned_reason("registry.example:5000/org/app").should eq "has no tag (implicitly latest)"
    ImageTag.unversioned_reason("org/app:stable").should eq "uses the moving tag stable, which names no version"
  end

  it "takes the repository from a reference, keeping the registry port", tags: ["versioned_tag"] do
    ImageTag.repository_of("coredns/coredns:1.6.7").should eq "coredns/coredns"
    ImageTag.repository_of("registry.example:5000/org/app:v2").should eq "registry.example:5000/org/app"
    ImageTag.repository_of("registry.example:5000/org/app").should eq "registry.example:5000/org/app"
    ImageTag.repository_of("org/app:1.0@sha256:abc").should eq "org/app"
  end

  it "finds the release before the deployed tag among tags of the same form (#2816)", tags: ["versioned_tag"] do
    ImageTag.previous_release("v4.3.0", ["v4.3.1", "v4.2.3", "v4.2.10", "v4.3.0", "v4.3.0-rc1", "latest"]).should eq "v4.2.10"
    ImageTag.previous_release("1.6.7", ["1.6.5", "1.6.6", "1.7.0", "1.6.7"]).should eq "1.6.6"
    ImageTag.previous_release("7.0.9-debian-12-r4", ["7.0.9-debian-12-r3", "7.0.9-debian-12-r5", "7.0.8-debian-12-r9"]).should eq "7.0.9-debian-12-r3"
    ImageTag.previous_release("stable-11248", ["stable-11146", "stable-11146-2", "stable-11248", "stable"]).should eq "stable-11146"
    ImageTag.previous_release("1.0.0", ["1.0.1", "2.0.0"]).should be_nil
    ImageTag.previous_release("latest", ["1.0.0"]).should be_nil
  end
end
