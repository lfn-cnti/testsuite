<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/cnti-logo-white.svg">
  <img align="right" alt="CNTi" src="docs/images/cnti-logo-color.svg" height="56">
</picture>

# CNTi Test Suite

[![Release](https://img.shields.io/github/v/release/lfn-cnti/testsuite)](https://github.com/lfn-cnti/testsuite/releases/latest)
[![Crystal Specs](https://github.com/lfn-cnti/testsuite/workflows/Crystal%20Specs/badge.svg)](https://github.com/lfn-cnti/testsuite/actions)
[![free5GC validation](https://github.com/lfn-cnti/testsuite/actions/workflows/free5gc_validation.yml/badge.svg)](https://github.com/lfn-cnti/testsuite/actions/workflows/free5gc_validation.yml)
[![OCUDU validation](https://github.com/lfn-cnti/testsuite/actions/workflows/ocudu_validation.yml/badge.svg)](https://github.com/lfn-cnti/testsuite/actions/workflows/ocudu_validation.yml)
[![License](https://img.shields.io/github/license/lfn-cnti/testsuite)](LICENSE)

**Check whether your network function is cloud native before your users find out.**

The CNTi Test Suite installs your CNF on Kubernetes, runs its tests against it, and tells you
exactly what to fix. It is an open source, vendor-neutral project of LF Networking's
[Cloud Native Telecom Initiative (CNTi)](https://lf-networking.atlassian.net/wiki/spaces/CNTi/pages/130416641/Cloud+Native+Telecom+Initiative+CNTi),
built on the [cloud native principles](https://networking.cloud-native-principles.org/) for
networking.

- **Broad coverage**: security, configuration, resilience with chaos experiments, microservice
  design, compatibility, observability and state.
- **Results you can act on**: every failure names the resource and the container, and says how to
  fix it.
- **Proven on real telecom workloads**: validated every night against free5GC, a 5G core, and the
  OCUDU gNB.
- **Runs where you work**: on your laptop with kind, on any cluster, or in CI with one GitHub Action
  step.

## See it run

<p align="center">
  <img alt="cnti-testsuite installs the CoreDNS example and runs four tests: three pass, one fails with the impacted resource and a remediation" src="docs/images/cnti-testsuite-demo.gif">
</p>

A passing test shows what it checked. A failing one names the resource and the container, and says
how to fix it. A test that could not measure says so instead of passing. Every run writes a results
file, and can print it as JSON or turn it into a JUnit report for your CI.

## Quick start

You need a Kubernetes cluster with at least two schedulable nodes (for example
[kind](https://kind.sigs.k8s.io/)), `kubectl` pointed at it, and `curl`. `setup` installs Helm if it
is missing.

```bash
source <(curl -s https://raw.githubusercontent.com/lfn-cnti/testsuite/main/curl_install.sh)
cnti-testsuite setup
curl -o cnti-testsuite.yaml https://raw.githubusercontent.com/lfn-cnti/testsuite/main/example-cnfs/coredns/cnti-testsuite.yaml
cnti-testsuite cnf_install --cnf-config ./cnti-testsuite.yaml
cnti-testsuite cert
```

`cert` runs the essential tests and takes about ten minutes for CoreDNS. `cnti-testsuite workload`
runs all of them, chaos experiments included.

Next steps: the [installation guide](INSTALL.md), the [usage guide](USAGE.md), and how to describe
your own CNF in [`cnti-testsuite.yaml`](CNTI_TESTSUITE_YAML_USAGE.md).

## Use it in CI

The [CNTi Test Suite GitHub Action](https://github.com/lfn-cnti/testsuite-action) creates a kind
cluster, installs your CNF and runs the `cert` tests on every pull request:

```yaml
- uses: lfn-cnti/testsuite-action@v1
  with:
    helm_chart_dir: charts/my-cnf
```

The job page gets a summary and an annotation for every failed test. With `badge_branch` set, the
action also publishes a badge for your README, showing the result of your default branch:

```markdown
![CNTi cert](https://github.com/<owner>/<repo>/raw/badges/cnti-badge.svg)
```

It looks like this, with the number of essential tests passed:
<img alt="CNTi cert: 17/19" src="docs/images/cnti-cert-badge-example.svg" height="20" align="top">

## What the suite checks

| Category | What is checked |
|---|---|
| Security | privileges, capabilities, host access, root users, seccomp and other Pod Security Standards controls, resource limits, service account tokens, network policies, credentials in configuration |
| Configuration | labels, image tags, default namespace, hard-coded IP addresses, NodePorts and host ports, secrets, immutable ConfigMaps, alpha APIs, operators |
| Reliability, resilience and availability | liveness and readiness probes, and chaos experiments: pod deletion, network latency, corruption and duplication, memory, disk and I/O stress, DNS errors |
| Compatibility, installability and upgradability | Helm charts, scaling up and down, rolling updates and rollback, CNI independence, deprecated APIs |
| Microservice | image size, startup time, one process type, service discovery, signal handling, zombie reaping, init systems, shared databases |
| Observability and diagnostics | logs, Prometheus metrics, OpenMetrics, log routing, tracing |
| State | node drain, elastic and local volumes, database persistence |

The [test documentation](docs/TEST_DOCUMENTATION.md) explains every test: what it measures, why
the practice matters, and how to fix a failure.

## Reference workloads

- **[free5GC](https://free5gc.org/)**, an open source 5G core, is the reference CNF of the suite.
  If a test and a real network function disagree, it shows us which of the two is right. See
  [`example-cnfs/free5gc`](example-cnfs/free5gc/README.md), and the announcements by
  [LF Networking](https://lfnetworking.org/introducing-free5gc-as-a-reference-cnf-for-the-cnti-test-suite/)
  and [free5GC](https://free5gc.org/blog/20260415/20260415/).
- **The [OCUDU](https://ocudu.org/) gNB**, a 5G base station, runs in test mode without a radio.
  See [`example-cnfs/ocudu`](example-cnfs/ocudu/README.md).

Both are validated every night. They need more of the host than CoreDNS (free5GC's UPF needs the
`gtp5g` kernel module), so start with CoreDNS for a first try.

## Contributing

We welcome new tests, example CNFs, fixes, documentation and bug reports.

- [Contributing guide](CONTRIBUTING.md)
- [Good first issues](https://github.com/lfn-cnti/testsuite/labels/good%20first%20issue) and
  [contributions welcome](https://github.com/lfn-cnti/testsuite/labels/contributions-welcome)
- Using the suite? Add your organisation to the [adopters](ADOPTERS.md).

## Community

- Chat with us on [LFN Zulip](https://linuxfoundation.zulipchat.com/), channel
  `#lfn-cnti-discussion`.
- Join the weekly CNTi community meeting:
  [details](https://lf-networking.atlassian.net/wiki/spaces/CNTi/pages/130416641/Cloud+Native+Telecom+Initiative+CNTi#Community-Meetings)
  and [minutes](https://docs.google.com/document/d/1yjL079TR0L1q__BRuhREeXfx5MtAmjPzbFZlZUeBsK4/edit).
- The community follows the [LF Code of Conduct](https://lfprojects.org/policies/code-of-conduct/).

## License

The CNTi Test Suite is available under the [Apache 2.0 license](LICENSE).

---

<p align="center">
  <a href="https://lfnetworking.org/">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/lfn-logo-white.svg">
      <img alt="LF Networking" src="docs/images/lfn-logo-color.svg" width="160">
    </picture>
  </a>
  <br>
  <sub>The CNTi Test Suite is developed in the Cloud Native Telecom Initiative, a project of LF Networking.</sub>
</p>
