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

  # The repository of an image reference, without its tag or digest; the
  # registry port stays ("registry:5000/org/image:1.2" is
  # "registry:5000/org/image").
  def self.repository_of(image : String) : String
    name = image.split("@").first
    slash = name.rindex('/') || -1
    colon = name.rindex(':')
    colon && colon > slash ? name[0...colon] : name
  end

  # A commit hash in a tag: 7 to 40 hex characters, at least one of them a
  # letter, between separators ("20261016_52af3689", "1.2.3-de11750b").
  COMMIT_HASH = /(?<=[_.-])(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?=$|[_.-])/

  # The form of a version tag and its numbers: "v4.3.0" is "v#.#.#" with
  # [4, 3, 0], "7.0.9-debian-12-r4" is "#.#.#-debian-#-r#" with
  # [7, 0, 9, 12, 4]. A commit hash is a label, not part of the version:
  # "ubuntu-24.04-avx2-20261016_52af3689" is "ubuntu-#.#-avx#-#_@" with
  # [24, 4, 2, 20261016]. Nil for a tag without a number, or one that ends in
  # "latest" ("ubuntu-24.04-avx2-latest"): it moves, and names no version.
  def self.version_form(tag : String) : {String, Array(Int64)}?
    return nil if tag =~ /(^|[_.-])latest$/
    labelled = tag.gsub(COMMIT_HASH, "@")
    numbers = labelled.scan(/\d+/).map { |m| m[0].to_i64? }
    return nil if numbers.empty? || numbers.any?(&.nil?)
    {labelled.gsub(/\d+/, "#"), numbers.compact}
  end

  # The release before the deployed tag: among the repository's tags, the
  # closest older one of the same form ("v4.3.0" takes "v4.2.3", never
  # "v4.3.0-rc1" or "latest"). Nil when there is none.
  def self.previous_release(deployed : String, tags : Array(String)) : String?
    form = version_form(deployed)
    return nil unless form
    best = nil
    best_numbers = [] of Int64
    tags.each do |tag|
      candidate = version_form(tag)
      next unless candidate && candidate[0] == form[0]
      next unless compare_versions(candidate[1], form[1]) < 0
      if best.nil? || compare_versions(candidate[1], best_numbers) > 0
        best = tag
        best_numbers = candidate[1]
      end
    end
    best
  end

  private def self.compare_versions(a : Array(Int64), b : Array(Int64)) : Int32
    a.each_with_index do |n, i|
      return 1 if i >= b.size
      c = n <=> b[i]
      return c unless c == 0
    end
    a.size < b.size ? -1 : 0
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
