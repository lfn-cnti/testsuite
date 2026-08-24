# CNTi Test Suite

| Main                                                                                                                                        |
| ------------------------------------------------------------------------------------------------------------------------------------------- |
| [![Build Status](https://github.com/lfn-cnti/testsuite/workflows/Crystal%20Specs/badge.svg)](https://github.com/lfn-cnti/testsuite/actions) [![free5GC validation](https://github.com/lfn-cnti/testsuite/actions/workflows/nightly_free5gc.yml/badge.svg)](https://github.com/lfn-cnti/testsuite/actions/workflows/nightly_free5gc.yml) |

The CNTi Test Suite is an open source and vendor neutral tool that can be used to validate a telco application's adherence to [cloud native principles](https://networking.cloud-native-principles.org/) and best practices. 

This Test Suite's focus area is one part of LF Networking's [Cloud Native Telecom Initiative (CNTi)](https://wiki.lfnetworking.org/pages/viewpage.action?pageId=113213592) and works closely with the [CNTi Best Practices](https://wiki.lfnetworking.org/display/LN/Best+Practices) and [CNTi Certification](https://wiki.lfnetworking.org/display/LN/Certification) focus areas.

## Installation and Usage

To get the CNTi Test Suite up and running, see the [Installation Guide](INSTALL.md).

#### To give it a try immediately you can use these quick install steps

Prereqs: Kubernetes cluster, wget, curl, helm 3.8.2 or greater (helm 4 supported) on your system already.

1. Install the latest test suite binary: `source <(curl -s https://raw.githubusercontent.com/lfn-cnti/testsuite/main/curl_install.sh)`
2. Run `setup` to prepare the cnf-testsuite: `cnf-testsuite setup`
3. Pull down an example CNF configuration to try: `curl -o cnf-testsuite.yml https://raw.githubusercontent.com/lfn-cnti/testsuite/main/example-cnfs/coredns/cnf-testsuite.yml`
4. Initialize the test suite for using the CNF: `cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml`
5. Run all of application/workload tests: `cnf-testsuite workload`

#### More Usage docs

Check out the [usage documentation](USAGE.md) for more info about invoking commands and logging.

## Cloud Native Test Categories

The CNTi Test Suite will inspect CNFs for the following characteristics:

- **Configuration** - The CNF's configuration should be managed in a declarative manner, using ConfigMaps, Operators, or other declarative interfaces.
- **Compatibility, Installability & Upgradability** - CNFs should work with any Certified Kubernetes product and any CNI-compatible network that meet their functionality requirements while using standard, in-band deployment tools such as Helm (version 3) charts.
- **Microservice** - The CNF should be developed and delivered as a microservice.
- **State** - The CNF's state should be stored in a custom resource definition or a separate database (e.g. etcd) rather than requiring local storage. The CNF should also be resilient to node failure.
- **Reliability, Resilience & Availability** - CNFs should be reliable, resilient and available to failures inevitable in cloud environments. CNFs should be tested to ensure they are designed to deal with non-carrier-grade shared cloud HW/SW platforms.
- **Observability & Diagnostics** - CNFs should externalize their internal states in a way that supports metrics, tracing, and logging.
- **Security** - CNF containers should be isolated from one another and the host. CNFs are to be verified against any common CVE or other vulnerabilities.

See the [Test Documentation](docs/TEST_DOCUMENTATION.md) for a complete overview of the tests.

## Reference CNF: free5GC

[free5GC](https://free5gc.org/), an open source 5G core, is the **reference CNF** for the CNTi Test Suite: a realistic telecom workload used to validate that the suite's tests work against carrier-grade CNFs, demonstrate cloud native best practices, and serve as a worked example for onboarding your own CNF.

- Try it: [example-cnfs/free5gc](example-cnfs/free5gc/README.md) — deployment guide (Helm chart via git submodule, kind cluster configuration, known limitations) and a ready-to-use `cnf-testsuite.yml`.
- It is exercised nightly in CI against the certification test set (see the badge above).
- Read the announcements: [LF Networking](https://lfnetworking.org/introducing-free5gc-as-a-reference-cnf-for-the-cnti-test-suite/) · [free5GC blog](https://free5gc.org/blog/20260415/20260415/)

For a lightweight first try of the test suite itself, start with the CoreDNS example from the quick install steps above — free5GC has additional host requirements (the `gtp5g` kernel module and unsafe sysctls for the UPF).

## Contributing

Welcome! We gladly accept contributions on new tests, example CNFs, updates to documentation, enhancements, bug reports, and more.

- [Contributing guide](CONTRIBUTING.md)
- [Good first issues](https://github.com/lfn-cnti/testsuite/labels/good%20first%20issue)
- [Contributions welcome](https://github.com/lfn-cnti/testsuite/labels/contributions-welcome)

## Communication and Community Meetings

- Join the conversation on [LFN Tech's Slack](https://lfntech.slack.com/) channel [#cnti](https://lfntech.slack.com/archives/C06HQGWK4NL)
- Join the weekly CNTi Community meeting
  - [Meeting details](https://lf-networking.atlassian.net/wiki/spaces/CNTi/pages/130416641/Cloud+Native+Telecom+Initiative+CNTi#Community-Meetings) 
  - [Meeting minutes](https://docs.google.com/document/d/1yjL079TR0L1q__BRuhREeXfx5MtAmjPzbFZlZUeBsK4/edit)


## Code of Conduct

The CNTi community follows the [LF's Code of Conduct](https://lfprojects.org/policies/code-of-conduct/).

## License Terms

The CNTi Test Suite is available under the [Apache 2 license](LICENSE.md).
