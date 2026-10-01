require "../spec_helper"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/utils/sbom_detection.cr"

# Pure unit specs for the SBOM detection helpers, without a network or a
# cluster. The manifests are trimmed to the fields the detection reads.

BUILDKIT_INDEX = JSON.parse(<<-JSON)
  {
    "mediaType": "application/vnd.oci.image.index.v1+json",
    "manifests": [
      {"digest": "sha256:aaa", "platform": {"architecture": "amd64", "os": "linux"}},
      {"digest": "sha256:att1", "platform": {"architecture": "unknown", "os": "unknown"},
       "annotations": {"vnd.docker.reference.digest": "sha256:aaa",
                       "vnd.docker.reference.type": "attestation-manifest"}}
    ]
  }
  JSON

def attestation_manifest(key : String, *predicates : String) : JSON::Any
  layers = predicates.map { |p| {"mediaType" => "application/vnd.in-toto+json", "annotations" => {key => p}} }
  JSON.parse({"layers" => layers.to_a}.to_json)
end

describe "SBOM detection helpers" do
  describe "image references" do
    it "strips the tag from a tagged image", tags: ["points"] do
      r = sbom_image_repo_and_digest("docker.io/library/nginx:1.27")
      r[:repo].should eq("docker.io/library/nginx")
      r[:digest].should be_nil
    end

    it "strips the tag from an image with both a tag and a digest", tags: ["points"] do
      r = sbom_image_repo_and_digest("registry.example.com:5000/foo/bar:1.2@sha256:abc123")
      r[:repo].should eq("registry.example.com:5000/foo/bar")
      r[:digest].should eq("sha256:abc123")
    end

    it "keeps a registry port and a bare name intact", tags: ["points"] do
      sbom_image_repo_and_digest("localhost:5000/myapp")[:repo].should eq("localhost:5000/myapp")
      sbom_image_repo_and_digest("busybox")[:repo].should eq("busybox")
    end

    it "fetches an image by tag, or by digest without the tag", tags: ["points"] do
      sbom_fetch_ref("docker.io/library/nginx:1.27").should eq("docker.io/library/nginx:1.27")
      sbom_fetch_ref("docker.io/library/nginx:1.27@sha256:abc").should eq("docker.io/library/nginx@sha256:abc")
    end

    it "builds the attestation-manifest reference without the tag", tags: ["points"] do
      sbom_digest_ref("docker.io/library/nginx:1.27", "sha256:att1").should eq("docker.io/library/nginx@sha256:att1")
      sbom_digest_ref("docker.io/library/nginx:1.27@sha256:aaa", "sha256:att1").should eq("docker.io/library/nginx@sha256:att1")
    end

    it "builds the cosign .att and .sbom tags", tags: ["points"] do
      sbom_cosign_tag("ghcr.io/o/img:v1", "sha256:abc", "att").should eq("ghcr.io/o/img:sha256-abc.att")
      sbom_cosign_tag("ghcr.io/o/img:v1@sha256:abc", "sha256:abc", "sbom").should eq("ghcr.io/o/img:sha256-abc.sbom")
    end
  end

  describe "attestation manifests" do
    it "lists only the attestation manifests of an index", tags: ["points"] do
      sbom_attestation_digests(BUILDKIT_INDEX).should eq(["sha256:att1"])
    end

    it "finds no attestation manifests in a single-platform manifest", tags: ["points"] do
      sbom_attestation_digests(JSON.parse(%({"layers": []}))).should be_empty
    end

    it "does not count a provenance-only attestation", tags: ["points"] do
      m = attestation_manifest(BUILDKIT_PREDICATE_ANNOTATION, "https://slsa.dev/provenance/v0.2")
      sbom_predicate_in_manifest(m, BUILDKIT_PREDICATE_ANNOTATION).should be_nil
    end

    it "finds an SPDX SBOM next to provenance", tags: ["points"] do
      m = attestation_manifest(BUILDKIT_PREDICATE_ANNOTATION,
        "https://slsa.dev/provenance/v0.2", "https://spdx.dev/Document")
      sbom_predicate_in_manifest(m, BUILDKIT_PREDICATE_ANNOTATION).should eq("https://spdx.dev/Document")
    end

    it "finds a CycloneDX SBOM", tags: ["points"] do
      m = attestation_manifest(BUILDKIT_PREDICATE_ANNOTATION, "https://cyclonedx.org/bom/v1.5")
      sbom_predicate_in_manifest(m, BUILDKIT_PREDICATE_ANNOTATION).should eq("https://cyclonedx.org/bom/v1.5")
    end

    it "finds an SPDX SBOM in a cosign .att", tags: ["points"] do
      m = attestation_manifest(COSIGN_PREDICATE_ANNOTATION, "https://spdx.dev/Document")
      sbom_predicate_in_manifest(m, COSIGN_PREDICATE_ANNOTATION).should eq("https://spdx.dev/Document")
    end

    it "does not count a cosign .att that carries only provenance", tags: ["points"] do
      m = attestation_manifest(COSIGN_PREDICATE_ANNOTATION, "https://slsa.dev/provenance/v1")
      sbom_predicate_in_manifest(m, COSIGN_PREDICATE_ANNOTATION).should be_nil
    end
  end
end
