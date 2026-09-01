## CNTi Test Suite Frequently Asked Questions

### General

<details> <summary>What is the CNTi Test Suite?</summary>
<p>

- The CNTi Test Suite program enables interoperability of Cloud native Network Functions (CNFs) from multiple vendors running on top of Kubernetes. The CNTi Test Suite's goal is to provide an open source test suite to demonstrate conformance and implementation of best practices for both open and closed source Cloud Native Network Functions.

</p>
</details>

<details> <summary>Can I contribute to the CNTi Test Suite?</summary>
<p>

- Yes. You can start by reading the [CNTi Test Suite Contributing Guidelines](CONTRIBUTING.md).

</p>
</details>

<details> <summary>Does the CNTi Test Suite community meet?</summary>
<p>

- Yes. The CNTi Test Suite team meets once a week on Thursdays at 14:15-15:00 UTC. You can find more info about the meeting [here.](CONTRIBUTING.md#community-meeting)

</p>
</details>

<details> <summary>Does CNTi Test Suite have a slack channel?</summary>
<p>

- Yes. We have a channel on [LFN Tech's Slack](https://lfntech.slack.com/) [#cnti](https://lfntech.slack.com/archives/C06HQGWK4NL).

</p>
</details>

<details> <summary>If I found a bug or I think it's a bug, how do I report it?</summary>
<p>

- If you would like to report a bug, please create a [new issue](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=bug&template=bug-report.md&title=%5BBUG%5D) (using the **Bug Report** Template).

</p>
</details>

<details> <summary>How do I request a new feature?</summary>
<p>

- If you would like to request an enhancement, please create a [new issue](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=enhancement&template=feature-request.md&title=%5BFeature%5D) (using the **Feature Request** Template).

</p>
</details>

<details> <summary>Can I request a new workload or platform test for the CNTi Test Suite?</summary>
<p>

- Yes. If you would like to request a new workload test, please create a [new issue](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=workload&template=new-workload-test.md&title=%5BWorkload%5D) (using the **New Workload Test** Template) or create a [new issue](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=platform&template=new-platform-test.md&title=%5BPlatform%5D) (using the **New Platform Test** Template).

</p>
</details>

### Technical and Usage

<details> <summary>Can I run the CNTi Test Suite without a Kubernetes cluster?</summary>
<p>

- In simple terms, no. You need some type of Kubernetes (K8s) cluster whether it's bare metal, kind, Docker and so on to run the CNTi Test Suite against your CNF.

</p>
</details>

<details> <summary>Does the CNTi Test Suite have any pre-requisites or other requirements to run?</summary>
<p>

- Yes. There are a few requirements for the CNTi Test Suite. You can read about the requirements in the [INSTALL Guide](INSTALL.md#prerequisites).

</p>
</details>

<details> <summary>How are points assigned for tests?</summary>
<p>

- Points are different for each test and workload but in general terms, pass defaults to 5 and fail is a -1. See [points.yml](https://github.com/lfn-cnti/testsuite/blob/main/embedded_files/points.yml) for more details on the different points for default scoring.

</p>
</details>

<details> <summary>What platforms are supported by the CNTi Test Suite?</summary>
<p>

- The CNTi Test Suite runs on most major Linux distributions, Mac OS X (Intel + source install only) and WSL (Windows Subsystem for Linux).

</p>
</details>

<details> <summary>Does the CNTi Test Suite support or run on other architectures besides amd64?</summary>
<p>

- Currently only amd64 (Intel) is supported.

</p>
</details>

<details> <summary>Can I run the CNTi Test Suite on clusters currently in use?</summary>
<p>

- Yes but it's not recommended. There is a destructive option that will test your nodes with reboots and recovery. We recommend that tests are run in an environment that is not currently used by others, typically in a test or dev environment setting.

</p>
</details>

<details> <summary>I ran several tests and missed the output of the results, are these lost or can I view past test results?</summary>
<p>

- All test results are stored in the results/ directory of where you installed the CNTi Test Suite in yaml format.

</p>
</details>

<details> <summary>Why is the CNTi Test Suite written in Crystal and not in other languages like Go?</summary>
<p>

- The short answer is [Crystal](https://crystal-lang.org) fit the criteria we looked at in a language at the time which needed to run external programs/test suites and internal tests - [Taylor Carpenter](https://app.slack.com/client/T08PSQ7BQ/G019HM3K54H/user_profile/U7HCKCW90) via https://slack.cncf.io/
- Usability for Humans - Crystal, puts readablility for humans as a priority, which is why its syntax heavily inspired by Ruby.
- Type checking system to help humans catch their errors earlier
- Compiled language for portability, reduced size, and performance
- Metaprogramming through Crystal's powerful macro system
- Concurrency throughy green threads, called fiberes, which communicate over channels like Go lang and Clojure
- Dependency management for libraries and applications via the [crystal manager Shards](https://github.com/crystal-lang/shards)

</p>
</details>

### Troubleshooting

<details> <summary>Running cnti-testsuite says "No found config" or similiar type errors?</summary>
<p>

- This may indicate that you are not pointing to a valid cnti-testsuite.yaml config file for your CNF. You may want to read or review the [INSTALL](INSTALL.md) instructions or the [USAGE Documentation](USAGE.md).

</p>
</details>
