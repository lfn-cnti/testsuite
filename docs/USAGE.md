# CNTI Test Suite CLI Usage Documentation

### Table of Contents

- [Overview](USAGE.md#overview)
- [Syntax and Usage](USAGE.md#syntax-for-running-any-of-the-tests)
- [Common Examples](USAGE.md#common-example-commands)
- [Exit Codes](USAGE.md#exit-codes)
- [Logging Options](USAGE.md#logging-options)

### Overview

The CNTI Test Suite can be run in production mode (using an executable) or in developer mode (using [crystal lang directly](INSTALL.md#source-install)). See the [pseudo code documentation](../PSEUDO-CODE.md) for examples of how the internals of WIP tests might work.

### Syntax for running any of the tests

```
# Production mode
./cnti-testsuite [options] <task> [<task> ...]

# Developer mode
crystal src/cnti-testsuite.cr -- [options] <task> [<task> ...]
```

Options are GNU-style and may appear anywhere on the line, as `--name VALUE`
or `--name=VALUE`; several task names run in order. `--skip <task>` leaves a
task out of a suite. `./cnti-testsuite help` lists every option; an unknown
option or task is a usage error (exit 64) with the closest match suggested.

```
./cnti-testsuite cnf_install --cnf-config ./cnti-testsuite.yaml --timeout 120
./cnti-testsuite all --skip resilience --strict
./cnti-testsuite liveness readiness
```

:star: \*Note: All usage commands in this document will use the production (binary executable) syntax unless otherwise stated.

- :heavy_check_mark: indicates implemented into stable release
- :bulb: indicates Proof of Concept
- :memo: indicates To Do
- :x: indicates WARNINGS\*

### Results Output

Every run prints a per-test line to stdout **and** writes a full results file.

#### On stdout

- :heavy_check_mark: **PASSED** — the test met best practice; points awarded.
- :x: **FAILED** — the test failed; no points.
- ⏭ **SKIPPED** — the test could not be executed (a helper tool failed to install, a timeout, a probe that could not start); no points, and the test still counts in the maximum.
- ⏭ **N/A** — the test does not apply to this CNF (its subject is absent: no Secret, no database, no persistent volume, no chart repository, no metrics, logging or tracing stack, no CNI that enforces policy); excluded from the maximum. A test reports N/A, never SKIPPED, when its subject is absent.
- 💥 **ERROR** — the test errored while running.

Failed/errored tests also print indented detail lines beneath the result:
`> impacted: <resource>`, `> remediation: <guidance>`, and free-form `> <note>` lines.

#### Results file

Each run writes a **timestamped YAML file** into the results directory — `cnti/results/` under the
current working directory unless redirected (see below):

```
cnti/results/cnti-testsuite-results-<YYYYMMDD-HHMMSS-mmm>.yml
```

A new file is created per run, and **`cnti/results/latest.yml` always points at the newest one** — a
relative symlink, repointed whenever a results file is created (a copy, kept current, on
filesystems without symlinks). Scripts should read `latest.yml` rather than sorting the
directory. Every run also ends with one stable line naming both paths:

```
Results: cnti/results/cnti-testsuite-results-<timestamp>.yml (latest: cnti/results/latest.yml)
```

#### JUnit report

Most CI systems render JUnit XML natively (GitLab's merge request widget, Jenkins, Azure DevOps).
`results_junit` converts a results file into one:

```
./cnti-testsuite results_junit                                    # the newest results file
./cnti-testsuite results_junit --results-file PATH --junit-file PATH
```

By default the report is written next to the results file with the `.xml` extension. It holds one
`<testsuite>` per test category and one `<testcase>` per test: a failed test carries a `<failure>`
with the message, and the `details`, `impacted_resources` and `remediation` as its body; an
errored test an `<error>`; skipped and not-applicable tests a `<skipped>`. The run's `status`,
`exit_code` and every `summary` field are `<properties>` of the root, so a consumer can show
"17 of 19 essential tests passed, threshold 15" without opening the YAML.

#### Evidence bundle

`evidence` writes what a project publishes next to its badge, from the newest results file (or
`--results-file PATH`), into `cnti/evidence/` (or `--output-dir PATH`):

```
./cnti-testsuite evidence
./cnti-testsuite evidence --results-file PATH --output-dir PATH
```

- `cnti-badge.svg`: the badge, the CNTi logo, the test set and the score (`CNTi essential 17/19`
  for a `cert` run, the task's name for any other task), green when the run met its objective,
  red when it did not, grey when it errored.
- `cnti-badge.json`: the same in [shields.io endpoint](https://shields.io/badges/endpoint-badge)
  format, with the monochrome logo.
- `cnti-evidence.json`: an [in-toto Statement](https://github.com/in-toto/attestation) with the
  [Test Result predicate](https://github.com/in-toto/attestation/blob/main/spec/predicates/test-result.md):
  the results file as the subject (by sha256 digest), the verdict, the passed and failed tests
  by name, and under `cnti` the fields a reader needs without opening the YAML (suite version,
  task, status, tests passed and maximum, points, criteria, run date). Schema:
  [`docs/cnti-evidence.schema.json`](cnti-evidence.schema.json). The statement says
  `self_published: true`: it is produced by the project's own run, not by a CNTi review.
- A copy of the results file and its JUnit report, so the directory is complete on its own.
- `config/`: the configuration the run used, as the install recorded it: the `cnti-testsuite.yaml`
  the CNF was installed from and every values file it names (`-f`, `--values`, `--set-file`),
  each listed in the statement's `configuration` with its digest. This is what lets a reader see
  what was set on top of the chart's defaults; it is published verbatim, so keep credentials out
  of values files (use `--set` from a secret). The files come from the installed CNF, so run
  `evidence` before `cnf_uninstall`; afterwards the bundle has no `config/` and the statement's
  `configuration` is empty.

A results file without a verdict (`status: running`) is refused: the run did not finish. The
GitHub Action and the GitLab CI/CD component publish this bundle; a job on any other CI runs
`evidence` after the tests and uploads the directory to a public URL.

#### Signing the evidence

A published bundle says what a run found; a signature says which pipeline produced it, so a
reader can trust a bundle from a repository they cannot see. `evidence` writes the statement
unsigned (`cnti.provenance.method: none`); the job that signs it replaces that block and puts
the signature files next to the bundle. Three methods, by what the CI offers:

- **Sigstore keyless**, where the CI has an OIDC identity (GitHub Actions, GitLab CI and the
  other issuers Fulcio supports). It proves the pipeline: the certificate names the workflow.

  ```
  cosign sign-blob cnti-evidence.json --bundle cnti-evidence.json.sigstore.json --yes
  # reader:
  cosign verify-blob cnti-evidence.json --bundle cnti-evidence.json.sigstore.json \
    --certificate-identity-regexp '^https://github.com/<owner>/<repo>/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

  Record: `method: sigstore-keyless`, `files: [cnti-evidence.json.sigstore.json]`, `identity`:
  the workflow URL the reader verifies against.

- **A project key**, where the CI has no OIDC identity (Jenkins and the like, or an air-gapped
  pipeline). It proves the publisher, not the pipeline; publish the public key with the bundle
  or at a stable URL.

  ```
  cosign sign-blob --key cosign.key cnti-evidence.json --output-signature cnti-evidence.json.sig
  # reader:
  cosign verify-blob --key cosign.pub --signature cnti-evidence.json.sig cnti-evidence.json
  ```

  (`gpg --detach-sign` and `gpg --verify` do the same with a GPG key.) Record: `method: key`,
  `files: [cnti-evidence.json.sig, cosign.pub]`, `identity`: the key's name or fingerprint.

- **GitHub artifact attestations**, on GitHub Actions: the workflow attests the results file with
  the statement's predicate (`actions/attest`, permissions `id-token: write` and
  `attestations: write`); GitHub stores the attestation, nothing is added to the bundle.

  ```
  # reader:
  gh attestation verify cnti-testsuite-results-<timestamp>.yml --owner <owner>
  ```

  Record: `method: github-attestation`, `files: []`, `identity: <owner>/<repo>`.

Sign the statement, not the badge: the statement names the results file by digest, so one
signature covers the verdict and the results. A signing failure, or an unreachable Sigstore,
must leave the bundle unsigned with `method: none`, never fail the run that produced it. The
GitHub Action and the GitLab CI/CD component do this when asked; the commands above are for
any other CI.

To write somewhere else, pass `--results-dir PATH` on the command line or set the
`CNTI_TESTSUITE_RESULTS_DIR` environment variable; the option wins over the variable. The
timestamped file and `latest.yml` both go there, and `delete_results` honours the same setting.

The file is rewritten after every test. While the run is in progress it says `status: running`
and `exit_code: null`; the verdict is written only when the run ends (or stops on `--strict`).
A run ended by a signal (SIGTERM from a cancelled CI job or the MCP server's `cancel_run`, SIGINT
from the terminal) is finalized too: the test under way is recorded as an error (`run stopped by
SIGTERM`), what it changed in the cluster is undone (a chaos engine and its fault, a cordoned node),
the file says `status: stopped` with `exit_code` 128 + the signal (143 for SIGTERM, 130 for SIGINT),
and the process exits with that code. A file still in the `running` state therefore belongs to a run
that could not say how it ended — a crash, a SIGKILL — and its `summary` shows only what had run by then.

A machine-readable [JSON Schema](cnti-testsuite-results.schema.json) describes the file
(matching the current `schema_version`); use it to validate output or generate types.

To consume results without reading a file, pass `--output json`. The results document is
printed to **stdout** as JSON — the same shape as the results file, so the schema above applies
verbatim (YAML is a JSON superset). In this mode every decorative line, score and progress
message goes to **stderr**, leaving stdout as a single JSON document, and the exit code is
unchanged (`0` the run met its objective, `1` it did not, `2` the suite errored, `64` a usage error).
The default is `--output text`.

```
./cnti-testsuite all --output json 1>results.json 2>run.log
```

Commands that write no results file — `cnf_install`, `setup` and the other lifecycle
commands — print **nothing** to stdout in JSON mode; their exit code is the only signal, so a
caller should not wait for a document that never comes. Usage errors (exit `64`) are reported on
**stderr** as well, so a caller parsing stdout sees an empty document rather than an error object.

##### Structure

```yaml
name: cnti testsuite
testsuite_version: v1.2.3
schema_version: 1                 # version of this results-file schema
status: failed                    # overall run verdict: passed | failed | error
command: ./cnti-testsuite all
exit_code: 1                      # 0 = run met its objective, 1 = did not, 2 = >=1 test errored
summary:                          # aggregate numbers for the whole run
  total: 18                       # tests executed
  passed: 12
  failed: 2
  skipped: 3
  na: 1
  error: 0
  max_passed: 14                  # maximum tests that could have passed (the denominator)
  essential_passed: 8
  essential_max_passed: 10
  points: 42
  maximum_points: 90
tools:                            # versions of the tools whose verdicts the file contains
  kubescape: 4.0.12
  kubescape_framework: nsa
  kubescape_regolibrary: 2.0.33
  kyverno: 1.19.0
  kyverno_policies: release-1.19
  litmus: 3.31.0
platform:                         # the cluster the tests ran on (null when it could not be queried)
  kubernetes: v1.32.0
  provider: kind                  # from the nodes' providerID; none when absent
  cni: kindnet                    # where a kube-system DaemonSet names it; null otherwise
  nodes:
    - name: kind-worker
      roles: []
      kubelet: v1.32.0
      os_image: Debian GNU/Linux 12 (bookworm)
      kernel: 6.8.0-1017-azure
      container_runtime: containerd://1.7.24
      architecture: amd64
      cpu: "4"
      memory: 16373844Ki
items:
  - name: privileged_containers
    status: failed                # passed | failed | skipped | na | error
    message: Found 2 privileged containers
    type: essential               # the test's declared type (essential | normal | bonus)
    points: 0
    start_time: "2026-07-07T10:00:00.000000000Z"   # RFC 3339
    end_time: "2026-07-07T10:00:03.000000000Z"
    task_runtime: 3.0                              # seconds
    remediation:                  # optional; present only when non-empty
      - Set securityContext.privileged=false on the offending containers
    impacted_resources:           # optional; present only when non-empty
      - kind: Deployment
        name: coredns-coredns
        namespace: cnti-default    # optional (omitted for cluster-scoped resources)
        container: coredns        # optional
        reason: privileged container
  - name: reasonable_startup_time
    status: failed
    message: CNF had a startup time over the limit
    type: normal
    points: 0
    start_time: "2026-07-07T10:00:04.000000000Z"
    end_time: "2026-07-07T10:00:49.000000000Z"
    task_runtime: 45.0
    details:                      # optional; free-form reasons/evidence
      - "CNF had a startup time of 45 seconds (limit: 30 seconds)"
```

##### Top-level fields

| Field | Description |
|-------|-------------|
| `name` | Always `cnti testsuite`. |
| `testsuite_version` | Version of the test suite that produced the file. |
| `schema_version` | Integer version of this results-file schema; bumped on breaking changes. |
| `status` | Overall run verdict, derived from `exit_code`: `passed` (0), `failed` (1), `error` (2), `stopped` (ended by a signal, 143 or 130); `running` until the run ends. |
| `command` | The command line that produced this file. |
| `exit_code` | Process exit code, answering "did this run meet its objective?" (`null` while the run is in progress). `2` at least one test errored (raised) - the suite itself broke, which always wins. Otherwise, for a run with a pass criterion (`cert`): `0` the criterion was met, `1` it was not. For a run without one (`all`, `workload`, `platform`): `0` no test failed (passed/skipped/na), `1` at least one test failed. Additionally, the process exits with `64` (usage error) on unknown or malformed command-line arguments, before any test runs. See [Exit codes](#exit-codes) for the full table. |
| `summary` | Aggregate numbers for the whole run (see below). |
| `tools` | Versions of the tools whose verdicts the file contains (see below). |
| `platform` | The cluster the tests ran on, recorded when the file is created: the API server version, the provider (from the nodes' `providerID`), the CNI where a `kube-system` DaemonSet names it, and every node with its kubelet version, OS image, kernel, container runtime, architecture and capacity. A score is only interpretable against the environment it was produced in. `null` when the cluster could not be queried; a run never fails because of it. |
| `items` | One entry per test that ran (see below). |

##### `tools` fields

What counts as a finding in the Kubescape, Kyverno and LitmusChaos based tests depends on the scanner and policy versions, so the file records the versions the suite pinned and installed. Two runs that disagree with different values here measured with different rulers; the per-test entries in `docs/TEST_DOCUMENTATION.md` name the control, policy or experiment each test reads.

| Field | Description |
|-------|-------------|
| `kubescape` | Kubescape CLI version. |
| `kubescape_framework` | Kubescape framework the security tests read their controls from (`nsa`). |
| `kubescape_regolibrary` | Release of [kubescape/regolibrary](https://github.com/kubescape/regolibrary) the framework was downloaded from. |
| `kyverno` | Kyverno CLI version. |
| `kyverno_policies` | Branch of [kyverno/policies](https://github.com/kyverno/policies) the audit policies are taken from. |
| `litmus` | LitmusChaos operator and chaos-charts version. |

##### `summary` fields

All counts/scores are scoped to the tests that actually ran.

| Field | Description |
|-------|-------------|
| `total` | Number of tests executed. |
| `passed` / `failed` / `skipped` / `na` / `error` | Count of items in each status. |
| `max_passed` | Maximum number of tests that could have passed (denominator for "X of Y tests passed"). |
| `essential_passed` / `essential_max_passed` | Passed vs. maximum-passable among `essential`-tagged tests. |
| `points` | Total points scored. |
| `maximum_points` | Maximum points achievable by the tests that ran. |
| `criteria` | Success-criterion verdict per task group that ran (see below). Absent when no such group ran. |

##### Test scoring

A test declares everything the suite knows about it at its own definition:

```crystal
scored_task "sysctls", emoji: "🔓🔑" do |t, args|          # an ordinary test
  ...
end

scored_task "liveness",
  type: CNFManager::TestType::Essential,                  # counts toward cert
  emoji: "⎈🧫" do |t, args|
  ...
end
```

The **type** decides the point value — `essential` 100, `normal` 5, `bonus` 1 —
so no test restates its own score, and the essential tests are by definition the
set that `cert` runs. `normal` is the default, so only the tests carrying a policy
decision say anything about their type. Everything else is read back rather than declared: a test's
**scope** from the namespace it registers in, and its **category** from the
aggregate that runs it. Individual `pass:`/`fail:` overrides exist for the rare
test that needs one.

There is no `points.yml`. The suite used to write one into the working directory
and read it straight back, so it needed a writable directory to read data it was
compiled with, and edits to the file were silently reverted on the next run.

##### Group success criteria

Every task group — the suites (`all`, `workload`, `cert`) and the
categories (`security`, `configuration`, ...) —
declares a success criterion in `Points::GROUP_CRITERIA`. These are group-level
policy — what `cert` requires of the essential tests, and what the suite demands of each category — so
they live together in one table:

```crystal
suite_task "cert", [...],
  scope: "essential",     # whose tests count
  min_passed: 15,         # how many of them must pass
  max_failed: CNFManager::NO_FAILURE_LIMIT   # the threshold accounts for failures
```

A group passes when **every** threshold it declares holds:

| threshold | default | meaning |
|-----------|---------|---------|
| `min_passed` | `0` | at least this many tests in scope passed |
| `min_ratio` | none | at least this share of the tests that **exist** in scope passed |
| `max_failed` | `0` | at most this many failed; `NO_FAILURE_LIMIT` for no limit |

`min_ratio` counts against how many tests are declared in scope rather than how
many a run reached, because excluding tests shrinks the latter — and `cert`
takes an `exclude` argument, so a ratio over it could be met by running less.

With the defaults — no floor, no ratio, no failures tolerated — a group passes
when nothing in it failed, which is what these groups have always demanded.
Only `cert` declares anything else.

Each evaluated group is recorded under `summary.criteria` in evaluation order:

```yaml
summary:
  criteria:
    - group: security
      scope: security
      min_passed: 0
      max_failed: 0
      passed_count: 17
      max_passed: 19
      failed_count: 2
      passed: false
```

A group's dependencies run before its body, so the **last** entry is the
outermost group, and its verdict is what `exit_code` reflects.

The same verdict is printed to stdout in a stable, greppable form:

```
Security: FAILED (2 of 19 tests failed)
Cert: PASSED (17 of 19 essential tests passed, threshold 15)
```

##### `items[]` fields

| Field | Description |
|-------|-------------|
| `name` | Test name (e.g. `privileged_containers`). |
| `status` | `passed`, `failed`, `skipped`, `na`, or `error`. |
| `message` | One-line verdict for the test. |
| `type` | The test's declared type (`essential`, `normal`, `bonus`). |
| `points` | Points awarded for this test. |
| `start_time` / `end_time` | RFC 3339 timestamps for the test's start and end. |
| `task_runtime` | Test duration in seconds (number). |
| `details` | *(optional)* Free-form reason/evidence strings; omitted when empty. |
| `remediation` | *(optional)* Guidance on how to fix the failure; omitted when empty. A failed test that provides none of its own carries the *Remediation* section of its entry in [TEST_DOCUMENTATION](TEST_DOCUMENTATION.md). |
| `impacted_resources` | *(optional)* Structured list of offending resources; omitted when empty. |

Each `impacted_resources` entry has `kind` and `name`, plus optional `namespace`, `container`, `pod`, and `reason` (present only when known).

---

### Logging Parameters

- **CNTI_TESTSUITE_LOG_LEVEL** environment variable: sets minimal log level to display: error (default); info; debug.
- **CNTI_TESTSUITE_LOG_PATH** environment variable: if set - all logs would be appended to the file defined by that variable.

#### Output streams

Result lines, scores and summaries are the suite's output and go to **stdout**; log messages are
diagnostics and go to **stderr** (or to the `CNTI_TESTSUITE_LOG_PATH` file when set). This means
`./cnti-testsuite <test> > results.txt 2> debug.log` cleanly separates the two even with
`CNTI_TESTSUITE_LOG_LEVEL=debug`. When capturing the streams separately, their relative ordering is not
guaranteed — merge them with `2>&1` if strict interleaving matters. Cursor-control progress
rewrites and colors are only emitted when stdout is a terminal.

---

### Exit codes

The exit code answers one question: did the invocation do what was asked?

| Code | Meaning | When |
|------|---------|------|
| `0` | Yes | A test run met its objective — for a run with a pass criterion (`cert`) the criterion was met, for any other run no test failed. A setup, install or uninstall command completed. |
| `1` | No | At least one test failed, or the criterion was not met. Or a command could not do its job: a precondition was missing (no kubeconfig, no CNF installed, a CNF already installed, a tool failed to install) or an operation failed. A message says which. |
| `2` | The suite itself broke | A test raised an unexpected exception, or the process crashed outside a test. Always wins over `1`. |
| `64` | Usage error | The command line was wrong: an unknown task, flag or argument; a malformed value; a required argument missing; an argument naming a file that does not exist. Detected before the requested operation starts. (sysexits `EX_USAGE`.) |
| `143`, `130` | Stopped | The run was ended by a signal (`143` SIGTERM: a cancelled CI job, the MCP server's `cancel_run`, a kill; `130` SIGINT: Ctrl-C). The test under way is recorded as an error, what it changed in the cluster is undone, and the results file says `status: stopped`. (128 + the signal, the shell convention.) |

A script that only needs pass/fail can test for `0`. A script that wants to tell "the CNF failed" (`1`) apart from "the suite or the invocation is broken" (`2`, `64`) can branch on the code.

---

### Common Example Commands

#### Building the executable

This is the command to build the binary executable if in developer mode or using the source install method ([requires crystal](INSTALL.md#source-install)):

```
crystal build src/cnti-testsuite.cr
```

#### Validating a cnti-testsuite.yaml file:

```
./cnti-testsuite validate_config --cnf-config [PATH_TO]/cnti-testsuite.yaml
```

#### Installing a cnf:

```
./cnti-testsuite cnf_install --cnf-config ./cnti-testsuite.yaml
```

##### Specify a timeout for resource readiness during installation:
```
./cnti-testsuite cnf_install --cnf-config ./cnti-testsuite.yaml --timeout 1800
```

##### Skip waiting for resource readiness during installation:
```
./cnti-testsuite cnf_install --cnf-config ./cnti-testsuite.yaml --skip-wait-for-install
```

##### When an installation fails

One CNF is installed at a time, so what a failed `cnf_install` leaves decides the next step:

- Nothing reached the cluster (a chart could not be pulled, a manifest directory is missing): run `cnf_install` again. What the failed run left in `cnti/installed-cnf/` is replaced.
- Part of the CNF is on the cluster (a later deployment failed, a workload did not become ready): run `cnf_uninstall` first, then install again.

`cnf_install` says which of the two applies.

#### Uninstalling a cnf:
```
./cnti-testsuite cnf_uninstall
```

##### Specify timeout for resource removal during uninstallation
```
./cnti-testsuite cnf_uninstall --timeout 60
```

##### Skip waiting for resource removal during uninstallation:
```
./cnti-testsuite cnf_uninstall --skip-wait-for-uninstall
```

#### Running all of the tests:

```
./cnti-testsuite all --cnf-config <path_to_your_config_file>/cnti-testsuite.yaml
```

#### Running all of the tests (including proofs of concepts)

```
./cnti-testsuite all --poc --cnf-config <path_to_your_config_file>/cnti-testsuite.yaml
```

#### Running all of the workload tests

```
crystal src/cnti-testsuite.cr -- workload --cnf-config <path_to_your_config_file>/cnti-testsuite.yaml
```

#### Running the essential tests (`cert`)

```
./cnti-testsuite cert
./cnti-testsuite cert --essential
./cnti-testsuite cert --skip increase_decrease_capacity --skip single_process_type
```

#### Running the workload tests:

```
./cnti-testsuite workload
```

#### Get available options and to see all available tests from command line:

`help` prints a usage page: the typical workflow, every option with its
meaning, and how to skip tasks or run several. `-h` and a bare invocation print
the same page.

```
./cnti-testsuite help
./cnti-testsuite -h
```

To list every task, grouped by category:

```
./cnti-testsuite help tasks
```

To see what a single task does, what it runs first, and which suites it belongs
to:

```
./cnti-testsuite help liveness
```

An unknown task name is answered with the closest match, e.g. `./cnti-testsuite
livenes` suggests `liveness`.

#### Shell completion:

`completion` prints a completion script for bash (default) or zsh, generated from the same
task and option registries `help` uses, so it always matches the binary that printed it:
namespaced task paths (`setup:install_kubescape`), every `--option` with its value (file names
after `--cnf-config` and the other path options, task names after `--skip`, `-l` log levels),
and further task names.

```
source <(./cnti-testsuite completion bash)     # this shell only
source <(./cnti-testsuite completion zsh)      # zsh (uses bashcompinit)
```

To make it permanent, add that line to `~/.bashrc` / `~/.zshrc`, or for bash drop the script
where bash-completion picks it up:

```
./cnti-testsuite completion bash > ~/.local/share/bash-completion/completions/cnti-testsuite
```

The script completes the binary name it was generated by (`cnti-testsuite` for the release
binary). To remove it: `complete -r cnti-testsuite`.

#### Print the version:

```
./cnti-testsuite --version
```

#### Clean up the CNTI Test Suite, the K8s cluster, and upstream projects:

```
./cnti-testsuite uninstall_all
```

This uninstalls the CNF and every helper the suite deployed into the cluster. The tools the suite downloaded for itself (kubescape and its framework, the kyverno CLI and policies, helm, the chaos experiments) stay under the suite home: each carries a version marker and is only downloaded again when the suite pins a different version. To delete them:

```
./cnti-testsuite tools_purge
```

---

### MCP server

`cnti-testsuite mcp` runs a [Model Context Protocol](https://modelcontextprotocol.io) server over
stdio (newline-delimited JSON-RPC 2.0), exposing the suite to AI agents. It is a thin transport over
the existing CLI: run tools re-invoke the binary with `--output json` and return the results document,
so everything it returns matches [the results schema](cnti-testsuite-results.schema.json). stdout
carries only JSON-RPC; logs and progress go to stderr.

This section is the reference. [MCP.md](MCP.md) is the how-to: registering the server with Claude
Code, Claude Desktop and VS Code, what it does to your cluster, example prompts and a recorded
session.

```
./cnti-testsuite mcp                  # no install or uninstall by default
./cnti-testsuite mcp --allow-install  # also expose cnf_install/cnf_uninstall
```

It implements MCP protocol version `2025-06-18`. The tools:

| Tool | What it does | Annotations |
|---|---|---|
| `list_tests` | Every test with its category and type (essential/normal/bonus) | read-only |
| `run_test` | Runs one test, as `cnti-testsuite <test>` does, and returns its results document when it finishes | |
| `start_run` | Starts a suite (`all`, `workload`, `cert`), a category or a single test, as `cnti-testsuite <name>` does, and returns a `runId` at once | |
| `get_run` | The state and progress of a run, with its results document once complete | read-only |
| `cancel_run` | Stops a run started by `start_run`, `cnf_install` or `cnf_uninstall` | |
| `get_results` | The newest results document in the workspace | read-only |
| `validate_config` | Checks a `cnti-testsuite.yaml`, as `cnti-testsuite validate_config` does, without installing anything; returns `valid` and the suite's messages | read-only |
| `cnf_install` / `cnf_uninstall` | Install or uninstall the CNF; only with `--allow-install`. Return a `runId`. | destructive |

A run through MCP is the CLI's run: `start_run cert` runs what `cnti-testsuite cert` runs, and the
results document is the one the CLI writes. Tests act on the cluster (they kill containers, change
images, scale workloads, inject faults and install tools), so the run tools carry no annotation
claiming otherwise, and an MCP host treats them as destructive by default and asks before each run.
Installing or removing a CNF is a different kind of action from testing the installed one, and is
available only when the server is started with `--allow-install`.

`run_test` answers when the test finishes: send a `progressToken` to receive progress notifications
meanwhile, and `notifications/cancelled` stops the test (a cancelled request gets no answer). A test
that can take longer than the client's tool-call timeout is better started with `start_run`: most
chaos tests take over a minute, and the TypeScript SDK times a tool call out after 60 s by default.
`start_run`, `cnf_install` and `cnf_uninstall` answer at once with a `runId`, so a run of any length
(a `cert` run can take over an hour) is followed with `get_run` and stopped with `cancel_run`. A run that ends without a results document reports the suite's last error
lines.

Cancelling sends SIGTERM to the suite process and the processes it started (a `helm` or `kubectl`
command running at that moment). The suite finalizes the run: the test under way is recorded as an
error, what it changed in the cluster is undone (a chaos test's engine and fault, a cordoned node),
and the results document, the newest one `get_results` returns, says `status: stopped` with
`exit_code: 143`.

For writing a `cnti-testsuite.yaml`, the server also offers two resources, embedded in the binary so
they match it: the configuration's JSON Schema
(`cnti-testsuite://docs/cnti-testsuite-config.schema.json`, the same file as
[cnti-testsuite-config.schema.json](cnti-testsuite-config.schema.json)) and the configuration guide
(`cnti-testsuite://docs/CNTI_TESTSUITE_YAML_USAGE.md`). An agent can read them, write the file and check
it with `validate_config`, which takes no run lock and needs no cluster, before it installs anything.

`--results-dir` given to `mcp` is passed on to every run, so that `get_results` reads where the runs
write; `CNTI_TESTSUITE_RESULTS_DIR` reaches them as it is.

Only one run uses the `cnti/` workspace and cluster at a time; a second run is refused, not queued.
When the client closes stdin, runs still going are stopped before the server exits. HTTP transport
and in-process execution are out of scope.

---

### Logging Options

#### Update the loglevel from command line:

```
# cmd line
./cnti-testsuite -l debug test
```

#### If in developer mode, make sure to use - - if running from source:

```
crystal src/cnti-testsuite.cr -- -l debug test
```

#### You can also use env var for logging:

```
CNTI_TESTSUITE_LOG_LEVEL=DEBUG ./cnti-testsuite test
```

:star: Note: When setting log level, the following is the order of precedence:

1. CLI or Command line flag
2. Environment variable
3. CNTi Test Suite [Config file](../config.yml) — `./config.yml` in the working directory, else `config.yml` in the suite home (`~/.cnti-testsuite`, relocatable via `CNTI_TESTSUITE_DIR`)

> Note: Available log levels are: `trace`, `debug`, `info`, `notice`, `warn`, `error` and `fatal`.

#### Environment variables for timeouts:

Timeouts are controlled by these environment variables, set them if default values aren't suitable:
```
CNTI_TESTSUITE_GENERIC_OPERATION_TIMEOUT=60
CNTI_TESTSUITE_RESOURCE_CREATION_TIMEOUT=120
CNTI_TESTSUITE_NODE_READINESS_TIMEOUT=240
CNTI_TESTSUITE_POD_READINESS_TIMEOUT=180
CNTI_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT=1800
CNTI_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION=30
CNTI_TESTSUITE_LABEL_RESOURCE_SLEEP=5
CNTI_TESTSUITE_OWNED_RESOURCE_DISCOVERY_TIMEOUT=60
```

#### Network retries:

Network-bound fetches (chart pulls, repo adds, binary downloads) are retried on transient
failures — resets, timeouts, DNS blips, 5xx — while a missing chart or auth error still fails
immediately:

```
CNTI_TESTSUITE_NETWORK_RETRY_ATTEMPTS=5   # attempts per fetch
CNTI_TESTSUITE_NETWORK_RETRY_BACKOFF=10   # base seconds between attempts (attempt N waits N x backoff: 10s, 20s, 30s, 40s)
```

#### Other environment variables:

- **CNTI_TESTSUITE_DIR**: the suite home (default `~/.cnti-testsuite`): where `config.yml` is looked up and where the tools the suite installs for itself are cached under `tools/`. Each cached tool carries a `<tool>.version` marker with the version it was installed at; a suite that pins a different version reinstalls it on the next run, so the cache never serves a stale tool.
- **CNTI_TESTSUITE_FORCE_INSTALL**: set (to any value) to reinstall the suite-managed local Helm even when an installation is already present.
- **CNTI_TESTSUITE_ENV**: set to `TEST` for test-mode shortcuts (smaller samples, quicker checks). Used by the spec suite; not meant for normal runs.
- **CNTI_TESTSUITE_RESULTS_DIR**: redirect the results directory; see [Results file](#results-file).
- **CNTI_TESTSUITE_CONTAINER_RUNTIME_SOCKET**: host path of the container runtime socket the LitmusChaos helpers use for `pod_io_stress`. By default the suite detects the runtime from the nodes and probes the usual socket locations (including the k3s, RKE2 and microk8s ones) on a node; set this when the cluster keeps the socket elsewhere. A cluster property, not part of the CNF config.

Every variable that configures the suite's own behavior carries the `CNTI_TESTSUITE_` prefix.
Credentials and ecosystem-wide standards deliberately keep their conventional names, so one
export serves every tool that honors them: `KUBECONFIG`, `GITHUB_TOKEN`,
`DOCKERHUB_USERNAME`/`DOCKERHUB_PASSWORD` (shared by `docker login`, `helm registry login`,
and the suite's registry queries — see [INSTALL.md](INSTALL.md)), `NO_COLOR`, and `HOME`.

#### Running The Linter

Ameba (https://github.com/crystal-ameba/ameba) is a static code linter for crystal-lang.
To run Ameba, testsuite needs to be installed in developer mode ([Source Install](INSTALL.md#source-install)) and Ameba needs to be installed using source method, which is mentioned in Ameba readme.md:

```
git clone https://github.com/crystal-ameba/ameba && cd ameba
make install
```

After that, follow the usage guidelines from the Ameba repository.

### Usage for categories and single tests

It's located in [TEST_DOCUMENTATION](TEST_DOCUMENTATION.md), Check for needed category or test there.
