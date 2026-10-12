# Security

## Reporting a vulnerability

Please do not open a public issue for a vulnerability in the suite or in what it installs on a
cluster. Report it privately through GitHub's
[private vulnerability reporting](https://github.com/lfn-cnti/testsuite/security/advisories/new)
for this repository, or by e-mail to the [maintainers](../MAINTAINERS.md).

You will get an acknowledgement within a week. The maintainers assess the report, agree a fix
and a disclosure date with you, and publish an advisory with the fix. Credit is given unless
you ask otherwise.

## Scope

In scope: the `cnti-testsuite` binary and its MCP server, the GitHub Action and the GitLab
CI/CD component, and the manifests and policies the suite applies to a cluster during `setup`
and a run. Out of scope: the CNFs under test, the example CNFs and spec fixtures (report those
to their own projects), and the third-party tools the suite installs (Kubescape, Kyverno,
LitmusChaos, Jaeger), which have their own processes.

## Supported versions

Fixes go into the latest release of the 2.x line. Older releases are not patched.
