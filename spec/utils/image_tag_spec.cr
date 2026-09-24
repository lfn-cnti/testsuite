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
end
