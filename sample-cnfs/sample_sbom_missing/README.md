# sample_sbom_missing

A CNF whose container image (`nginx:1.21.0`, published 2021) has no discoverable
SBOM. The `sbom_available` security test should fail against it and report the
image as an impacted resource.
