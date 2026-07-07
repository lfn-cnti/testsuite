# CNTI Test Suite CLI Usage Documentation

### Table of Contents

- [Overview](USAGE.md#overview)
- [Syntax and Usage](USAGE.md#syntax-for-running-any-of-the-tests)
- [Common Examples](USAGE.md#common-example-commands)
- [Logging Options](USAGE.md#logging-options)

### Overview

The CNTI Test Suite can be run in production mode (using an executable) or in developer mode (using [crystal lang directly](INSTALL.md#source-install)). See the [pseudo code documentation](PSEUDO-CODE.md) for examples of how the internals of WIP tests might work.

### Syntax for running any of the tests

```
# Production mode
./cnf-testsuite <testname>

# Developer mode
crystal src/cnf-testsuite.cr <testname>
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
- ⏭ **SKIPPED** — the test was not executed (a reason is printed); no points.
- ⏭ **N/A** — the test does not apply to this CNF (the feature under test is absent); excluded from scoring.
- 💥 **ERROR** — the test errored while running.

Failed/errored tests also print indented detail lines beneath the result:
`> impacted: <resource>`, `> remediation: <guidance>`, and free-form `> <note>` lines.

#### Results file

Each run writes a **timestamped YAML file** to the `results/` directory of the current working
directory (the path is also logged at startup):

```
results/cnf-testsuite-results-<YYYYMMDD-HHMMSS-mmm>.yml
```

A new file is created per run. To grab the latest programmatically:

```
ls -t results/cnf-testsuite-results-*.yml | head -1
```

A machine-readable [JSON Schema](docs/cnf-testsuite-results.schema.json) describes the file
(matching the current `schema_version`); use it to validate output or generate types.

##### Structure

```yaml
name: cnf testsuite
testsuite_version: v1.2.3
schema_version: 1                 # version of this results-file schema
status: failed                    # overall run verdict: passed | failed | error
command: ./cnf-testsuite all
exit_code: 1                      # 0 = passed, 1 = failed, 2 = error (critical)
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
items:
  - name: privileged_containers
    status: failed                # passed | failed | skipped | na | error
    message: Found 2 privileged containers
    type: essential               # scoring class from points.yml (essential | bonus | normal | cert | ...)
    points: 0
    start_time: "2026-07-07T10:00:00.000000000Z"   # RFC 3339
    end_time: "2026-07-07T10:00:03.000000000Z"
    task_runtime: 3.0                              # seconds
    remediation:                  # optional; present only when non-empty
      - Set securityContext.privileged=false on the offending containers
    impacted_resources:           # optional; present only when non-empty
      - kind: Deployment
        name: coredns-coredns
        namespace: cnf-default    # optional (omitted for cluster-scoped resources)
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
| `name` | Always `cnf testsuite`. |
| `testsuite_version` | Version of the test suite that produced the file. |
| `schema_version` | Integer version of this results-file schema; bumped on breaking changes. |
| `status` | Overall run verdict, derived from `exit_code`: `passed` (0), `failed` (1), `error` (2). |
| `command` | The command line that produced this file. |
| `exit_code` | Process exit code: `0` passed, `1` failed (a required test failed), `2` error (a test raised). |
| `summary` | Aggregate numbers for the whole run (see below). |
| `items` | One entry per test that ran (see below). |

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

##### `items[]` fields

| Field | Description |
|-------|-------------|
| `name` | Test name (e.g. `privileged_containers`). |
| `status` | `passed`, `failed`, `skipped`, `na`, or `error`. |
| `message` | One-line verdict for the test. |
| `type` | Scoring class from `points.yml` (`essential`, `bonus`, `normal`, `cert`, …). |
| `points` | Points awarded for this test. |
| `start_time` / `end_time` | RFC 3339 timestamps for the test's start and end. |
| `task_runtime` | Test duration in seconds (number). |
| `details` | *(optional)* Free-form reason/evidence strings; omitted when empty. |
| `remediation` | *(optional)* Guidance on how to fix the failure; omitted when empty. |
| `impacted_resources` | *(optional)* Structured list of offending resources; omitted when empty. |

Each `impacted_resources` entry has `kind` and `name`, plus optional `namespace`, `container`, `pod`, and `reason` (present only when known).

---

### Logging Parameters

- **LOG_LEVEL** environment variable: sets minimal log level to display: error (default); info; debug.
- **LOG_PATH** environment variable: if set - all logs would be appended to the file defined by that variable.

---

### Common Example Commands

#### Building the executable

This is the command to build the binary executable if in developer mode or using the source install method ([requires crystal](INSTALL.md#source-install)):

```
crystal build src/cnf-testsuite.cr
```

#### Validating a cnf-testsuite.yml file:

```
./cnf-testsuite validate_config cnf-config=[PATH_TO]/cnf-testsuite.yml
```

#### Installing a cnf:

```
./cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml
```

##### Specify a timeout for resource readiness during installation:
```
./cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml timeout=1800
```

##### Skip waiting for resource readiness during installation:
```
./cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml skip_wait_for_install
```

#### Uninstalling a cnf:
```
./cnf-testsuite cnf_uninstall
```

##### Specify timeout for resource removal during uninstallation
```
./cnf-testsuite cnf_uninstall timeout=60
```

##### Skip waiting for resource removal during uninstallation:
```
./cnf-testsuite cnf_uninstall skip_wait_for_uninstall
```

#### Running all of the platform and workload tests:

```
./cnf-testsuite all cnf-config=<path_to_your_config_file>/cnf-testsuite.yml
```

#### Running all of the tests (including proofs of concepts)

```
./cnf-testsuite all poc cnf-config=<path_to_your_config_file>/cnf-testsuite.yml
```

#### Running all of the workload tests

```
crystal src/cnf-testsuite.cr workload
cnf-config=<path_to_your_config_file>/cnf-testsuite.yml
```

#### Running certification tests

```
./cnf-testsuite cert
./cnf-testsuite cert essential
./cnf-testsuite cert exclude="increase_decrease_capacity single_process_type"
```

#### Running all of the platform or workload tests independently:

##### Run workload only tests:

```
./cnf-testsuite workload
```

##### Run platform only tests (long running):

```
./cnf-testsuite platform
```

#### Get available options and to see all available tests from command line:

```
./cnf-testsuite help
```

#### Clean up the CNTI Test Suite, the K8s cluster, and upstream projects:

```
./cnf-testsuite uninstall_all
```

---

### Logging Options

#### Update the loglevel from command line:

```
# cmd line
./cnf-testsuite -l debug test
```

#### If in developer mode, make sure to use - - if running from source:

```
crystal src/cnf-testsuite.cr -- -l debug test
```

#### You can also use env var for logging:

```
LOGLEVEL=DEBUG ./cnf-testsuite test
```

:star: Note: When setting log level, the following is the order of precedence:

1. CLI or Command line flag
2. Environment variable
3. CNF-Testsuite [Config file](config.yml)

> Note: Available log levels are: `trace`, `debug`, `info`, `notice`, `warn`, `error` and `fatal`.

#### Environment variables for timeouts:

Timeouts are controlled by these environment variables, set them if default values aren't suitable:
```
CNF_TESTSUITE_GENERIC_OPERATION_TIMEOUT=60
CNF_TESTSUITE_RESOURCE_CREATION_TIMEOUT=120
CNF_TESTSUITE_NODE_READINESS_TIMEOUT=240
CNF_TESTSUITE_POD_READINESS_TIMEOUT=180
CNF_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT=1800
CNF_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION=90
CNF_TESTSUITE_LABEL_RESOURCE_SLEEP=5
```

#### Running The Linter

Ameba (https://github.com/crystal-ameba/ameba) is a static code linter for crystal-lang.
To run Ameba, testsuite needs to be installed in developer mode ([Source Install](INSTALL.md#source-install)) and Ameba needs to be installed using source method, which is mentioned in Ameba readme.md:

```
git clone https://github.com/crystal-ameba/ameba && cd ameba
make install
```

After that, follow the usage guidelines from the Ameba repository.

### Usage for categories and single tests

It's located in [TEST_DOCUMENTATION](docs/TEST_DOCUMENTATION.md), Check for needed category or test there.
