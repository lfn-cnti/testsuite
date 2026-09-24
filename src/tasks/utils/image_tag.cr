# What makes a container image reference "versioned", for versioned_tag:
# it pins one build of the image. A digest does that by construction; a
# tag does it when it is present, is not "latest" and names a version,
# for which the rule is that it contains a digit ("1.2.3", "v2",
# "6.0.2-debian-11-r0", "20240101"). Moving tags ("latest", "stable",
# "main", "dev") and untagged images (implicitly latest) do not.
module ImageTag
  # The tag of an image reference, or nil when it has none; the registry
  # port ("registry:5000/org/image") is not a tag.
  def self.tag_of(image : String) : String?
    last = image.split("@").first.split("/").last
    return nil unless last.includes?(":")
    last.rpartition(":")[2]
  end

  def self.digest?(image : String) : Bool
    image.includes?("@sha256:")
  end

  # Nil when the reference is versioned, otherwise why it is not.
  def self.unversioned_reason(image : String) : String?
    return nil if digest?(image)
    tag = tag_of(image)
    return "has no tag (implicitly latest)" if tag.nil? || tag.empty?
    return "uses the latest tag" if tag == "latest"
    return "uses the moving tag #{tag}, which names no version" unless tag =~ /\d/
    nil
  end
end
