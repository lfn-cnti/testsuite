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

- :heavy_check_mark: PASSED indicates it meets best practice, positive points given.
- ⏭ SKIPPED indicates the test was skipped (output should provide a reason), no points given.
- :x: FAILED indicates the test failed, negative points given.

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

##### Skip waiting for resource readiness during installation:
```
./cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml skip_wait_for_install
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
