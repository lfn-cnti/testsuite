require "json"

# SBOM detection helpers, kept in a separate file so they can be unit-tested
# without a network, a cluster or the task macros. `sbom_available_for_image?`
# in security.cr does the skopeo calls and hands the manifests to these.

# The SBOM predicate types the test recognises.
SBOM_PREDICATE_TYPES = [
  "https://spdx.dev/Document",
  "https://cyclonedx.org/bom",
]

def sbom_predicate?(predicate : String?) : Bool
  return false unless predicate
  SBOM_PREDICATE_TYPES.any? { |t| predicate.starts_with?(t) }
end

# Splits an image reference into its repository (always without a tag) and,
# when present, its digest. `foo:1.2@sha256:...` gives repo `foo`.
def sbom_image_repo_and_digest(image : String) : NamedTuple(repo: String, digest: String?)
  name = image
  digest = nil
  if (at = image.rindex('@'))
    name = image[0...at]
    digest = image[(at + 1)..]
  end
  last_slash = name.rindex('/') || -1
  if (colon = name.rindex(':')) && colon > last_slash
    name = name[0...colon]
  end
  {repo: name, digest: digest}
end

# The reference skopeo can fetch: skopeo rejects a reference with both a tag and
# a digest, so a digest reference drops the tag.
def sbom_fetch_ref(image : String) : String
  parts = sbom_image_repo_and_digest(image)
  (digest = parts[:digest]) ? "#{parts[:repo]}@#{digest}" : image
end

# The reference of a manifest in the same repository, by digest.
def sbom_digest_ref(image : String, digest : String) : String
  "#{sbom_image_repo_and_digest(image)[:repo]}@#{digest}"
end

# The cosign tag for an image digest, e.g. `repo:sha256-<hex>.att` or `.sbom`.
def sbom_cosign_tag(image : String, digest : String, suffix : String) : String
  "#{sbom_image_repo_and_digest(image)[:repo]}:#{digest.sub(":", "-")}.#{suffix}"
end

# Digests of the BuildKit attestation manifests listed in an image index.
def sbom_attestation_digests(index : JSON::Any) : Array(String)
  manifests = index.dig?("manifests").try(&.as_a?) || [] of JSON::Any
  manifests.compact_map do |m|
    next unless m.dig?("annotations", "vnd.docker.reference.type").try(&.as_s?) == "attestation-manifest"
    m.dig?("digest").try(&.as_s?)
  end
end

# The SBOM predicate type of an attestation manifest, or nil when it carries
# none (for example provenance only). `key` is the layer annotation that
# holds the predicate type: `in-toto.io/predicate-type` for BuildKit, and
# `predicateType` for cosign `.att`.
def sbom_predicate_in_manifest(manifest : JSON::Any, key : String) : String?
  layers = manifest.dig?("layers").try(&.as_a?) || [] of JSON::Any
  layers.each do |layer|
    predicate = layer.dig?("annotations", key).try(&.as_s?)
    return predicate if sbom_predicate?(predicate)
  end
  nil
end

BUILDKIT_PREDICATE_ANNOTATION = "in-toto.io/predicate-type"
COSIGN_PREDICATE_ANNOTATION   = "predicateType"
