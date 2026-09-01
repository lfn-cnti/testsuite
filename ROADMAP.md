CNTi Test Suite Roadmap
---

This document defines a high level roadmap for the CNTi Test Suite.

The following is a selection of some of the major features the CNTi Test Suite team plans to explore. This roadmap will continue to be updated as priorities evolve. 

To get a more complete overview of planned features and current work see the [project board](https://github.com/lfn-cnti/testsuite/projects/1), [issue tracker](https://github.com/lfn-cnti/testsuite/issues) and [milestones](https://github.com/lfn-cnti/testsuite/milestones) in GitHub.

### Create tests

- Build tests for Kubernetes best practices that address issues voiced by the end users, including:
    - On-boarding (day 1) items
    - CNF WG best practices
- Build [resilience tests](https://github.com/lfn-cnti/testsuite/blob/main/docs/TEST_DOCUMENTATION.md#category-reliability-resilience--availability-tests) using [LitmusChaos](https://litmuschaos.io/) experiments
- Create [observability tests](https://github.com/lfn-cnti/testsuite/blob/main/docs/TEST_DOCUMENTATION.md#category-observability--diagnostic-tests) to check for cloud native monitoring
- Create [state tests](https://github.com/lfn-cnti/testsuite/blob/main/docs/TEST_DOCUMENTATION.md#category-state-tests) to check cloud native data handling
- Create [security tests](https://github.com/lfn-cnti/testsuite/blob/main/docs/TEST_DOCUMENTATION.md#category-security-tests)

### Enhance the functionality of the test suite framework

- Add support for [air gapped](https://github.com/lfn-cnti/testsuite/labels/air-gapped) environments
- Add best practice suggestions to test results
- Split libraries out into different repositories under a single organization

### Onboard maintainers

- Document a Governance structure for maintainers
- Document a Contributor Ladder for maintainer levels
- Publish a "Getting Started with the CNTi Test Suite" blog post
- Create "Office Hours" and [good first issues](https://github.com/lfn-cnti/testsuite/labels/good%20first%20issue) to help beginners
- Engage CNCF-hosted projects and propose test ideas using their software
- Enlist help from other communities
    - Crystal Lang
    - CNCF Technical Advisory Groups (TAGs) 
    - Kubernetes Special Interest Groups (SIGs)

### Onboard end users

- Create ADOPTERS.md file to list users of the CNTi Test Suite 
- Set up [Calendly](https://calendly.com/cnftestsuite) to schedule presentations
- Offer presentations, demonstrations and assistance on the CNTi Test Suite to Service Providers and CNF Developers
    - To request a presentation, please open an [issue](https://github.com/lfn-cnti/testsuite/issues/new) or schedule via [Calendly](https://calendly.com/cnftestsuite)
- Promote test suite with new groups and communities
    - Present at Network of the Future (NoF) seminar
