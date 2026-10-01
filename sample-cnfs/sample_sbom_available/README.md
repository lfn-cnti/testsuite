# sample_sbom_available

A CNF whose container image ships an SBOM. It uses a recent Docker Official
Image (`nginx:1.27`) built with BuildKit, which attaches an SBOM/provenance
attestation manifest discoverable from the image index. The `sbom_available`
security test should pass against it.

NOTE: which public image reliably carries a discoverable SBOM in CI is an open
question for maintainers — see the PR description.
