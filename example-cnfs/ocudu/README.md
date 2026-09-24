# OCUDU gNB

[OCUDU](https://gitlab.com/ocudu/ocudu) is the open CU/DU by SRS: a 5G gNB
(CU-CP, CU-UP and DU) packaged as one container. This example installs the
upstream `ocudu-gnb` Helm chart from the OCUDU OCI registry and runs it in
**test mode** on a plain Kubernetes cluster:

- no core network: the CU-CP runs standalone (`no_core: true`);
- no radio unit: `ru_dummy` replaces the fronthaul, so the DU still runs its
  full L1/L2 without an SR-IOV NIC;
- a built-in traffic generator emulates one UE with PDSCH and PUSCH active.

Everything except the fronthaul is exercised, which is what the test suite
needs to install, scale, roll, and chaos-test the workload.

## Files

- `cnti-testsuite.yaml`: the test suite config; the second, retained image
  tag drives the rolling update, downgrade, version change and rollback tests.
- `gnb-values.yaml`: chart values sized for a four-vCPU node, one 20 MHz
  1x1 cell, no hugepages, no host path volume. Each choice is explained in
  the file.

The image is an AVX2 build with a retained `-stable` tag: the validation
runners do not guarantee AVX-512, and plain nightly tags are deleted after
30 days.

## Running

```bash
./cnti-testsuite setup
./cnti-testsuite cnf_install --cnf-config ./example-cnfs/ocudu/cnti-testsuite.yaml --timeout 1800
./cnti-testsuite cert        # or: workload
./cnti-testsuite cnf_uninstall
```

The `OCUDU validation` workflow runs both suites nightly on a kind cluster.
Findings from the last full run are tracked in
[issue #2559](https://github.com/lfn-cnti/testsuite/issues/2559).
