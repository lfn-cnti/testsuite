## Installing the CNTI Test Suite from Source

### Overview

This INSTALL guide will detail the minimum requirements needed for cnf-testsuite to install from source.

### Table of Contents

- [**Pre-Requisites**](#Pre-Requisites)
- [**Installation**](#Installation)
- [**Preparation**](#Preparation)
- [**Configuration**](#Configuration)
- [**Running cnf-testsuite for the first time**](#Running-cnf-testsuite-for-the-first-time)

### Pre-Requisites

#### Requirements

- **kubernetes multi-node cluster** _(Working k8s cluster, see [supported k8s and installation details](#Details-on-supported-k8s-clusters-and-installation) on installation._
- **kubectl** _(run commands against k8 clusters, see [installing kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) for more details._
- **curl**
- **helm 3.8.2** _or newer_ _(cnf-testsuite installs if not found locally)_
- **git** _(used to check out code from github)_
- **crystal-lang** version >=1.15.1 _(to compile the source and build the binary, see [crystal installation](https://crystal-lang.org/install/)) for more information._
- **shards** ([dependency manager](https://github.com/crystal-lang/shards) for crystal-lang)

##### Optional Requirement

- **docker** (for building from crystal alpine image)

#### Details on supported K8s clusters and installation:

<details><summary>Click here to drop down details</summary>

<p>

##### Supported K8s Clusters

- [Access](https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/) to a working [Certified K8s](https://cncf.io/ck) cluster via [KUBECONFIG environment variable](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/#set-the-kubeconfig-environment-variable). (See [K8s Getting started guide](https://kubernetes.io/docs/setup/) for options)
- Follow the optional instructions below if you don't already have a K8s cluster setup
- Multi-node cluster with at least 2 schedulable nodes

##### Kind

- Follow the [kind install](KIND-INSTALL.md) instructions to setup a cluster in [kind](https://kind.sigs.k8s.io/)

##### k8s-infra

- You can clone the CNF-Testbed project if you have an account at Equinix Metal (formerly Packet.net). Get the code by running the following:

```
git clone https://github.com/cncf/cnf-testbed.git
```

- Clone the K8s-infra repo then Follow the [prerequisites](https://github.com/cncf/cnf-testbed/tree/master/tools#pre-requisites) for [deploying a K8s cluster](https://github.com/cncf/cnf-testbed/tree/master/tools#deploying-a-kubernetes-cluster-using-the-makefile--ci-tools) for a Equinix Metal host.
- If you already have IP addresses for your provider, and you want to manually install a K8s cluster, you can use k8s-infra to do this within your cnf-testbed repo clone.

```
cd tools/ && git clone https://github.com/crosscloudci/k8s-infra.git
```

- Now follow the [K8s-infra quick start](https://github.com/crosscloudci/k8s-infra/blob/master/README.md#quick-start) for instructions on how to install.

</p>
</details>

### Installation

We can assume you have access to a working kubernetes cluster. We recommend only running the cnf-testsuite on dev or test clusters. The source install steps have been verified on most Linux distributions (Ubuntu, Debian and CentOS), Mac OS X and WSL as long as crystal-lang >=v1.15.1 is installed.

_NOTE: Currently Mac OS X users will need to ensure helm 3.1.1 or greater is installed locally._

- Verify your KUBECONFIG points to your correct k8s cluster:
  ```
  echo $KUBECONFIG
  ```
  If there's no output or it's pointed to the wrong config, run the export to the correct config:
  ```
  export KUBECONFIG=yourkubeconfig
  ```
- Verify your cluster is accessible with kubectl (this command should provide information about your kubernetes cluster):
  ```
  kubectl cluster-info
  ```
- You'll need cystal-lang >=v1.15.1 installed with [shards](https://github.com/crystal-lang/shards). You can follow their [install instructions](https://crystal-lang.org/install/) for their different install methods.
- cnf-testsuite needs helm-3.1.1 or greater but is optional as the prerequisite checks will install if not found. You can install helm by checking their [installation methods](https://helm.sh/docs/helm/helm_install/).
- Checkout the source code with git:
  ```
  git clone git@github.com:lfn-cnti/testsuite.git
  ```
- Change directory into the source:
  ```
  cd cnf-testsuite
  ```
- Now we need to run shards to pull down requirements needed to build and compile cnf-testsuite:
  ```
  shards install
  ```
- Now build a cnf-testsuite binary (this method will have runtime dependencies but should not pose any issues):
  ```
  crystal build src/cnf-testsuite.cr
  ```
  This should create an executable `cnf-testsuite` binary in your source checkout.

<details><summary>(Optional) Build cnf-testsuite using Docker  Alpine Image</summary>
<p>

We use the official crystal alpine docker image for builds; seen in [actions.yml](.github/workflows/actions.yml)

_This build method is static and DOES NOT have any runtime dependencies._

- To build using docker crystal alpine image (great if you don't have crystal installed)

```
docker pull crystallang/crystal:1.15.1-alpine-build
 ## Note: $PWD is your cnf-testsuite source directory in the following commands 
docker run --rm -it -v $PWD:/workspace -w /workspace crystallang/crystal:1.15.1-alpine-build shards install
docker run --rm -it -v $PWD:/workspace -w /workspace crystallang/crystal:1.15.1-alpine-build crystal build src/cnf-testsuite.cr --release --static --link-flags "-lxml2 -llzma"
```

</p>
</details>

<details> <summary>(Optional) Install Tab Completion</summary>

<p>
NOTE: Also compatible with the installation styles from kubectl completion install if you prefer
https://kubernetes.io/docs/tasks/tools/install-kubectl/#enable-kubectl-autocompletion

You will need to have cnf-testsuite executable in your current PATH for this to work properly.

```
./cnf-testsuite completion -l error > test.sh
source test.sh
```

</p>
</details>

<details><summary>Other Information on Crystal Builds</summary>
<p>
The CNTI Test Suite is modeled after make, or if you're familiar with Ruby, [rake](https://github.com/ruby/rake). Tests are created via tasks using the Crystal library, [SAM.cr](https://github.com/imdrasil/sam.cr).

To run the automated test suite within the source clone:

```
crystal spec
```

</p></details>

### Preparation

Now that we have a `cnf-testsuite` binary, we can run `setup` to ensure it has all the pre-requisites needed in order to successfully run tests and prepare required installed_cnf_files/ directory and other files required for cnf-testsuite.

- Run the following to prepare cnf-testsuite:
  ```
  ./cnf-testsuite setup
  ```
- If you have crystal installed, you can also run by:
  ```
  crystal src/cnf-testsuite.cr setup
  ```
  This should display output of all the pre-requisites (and install helm if not found on the system you intend to run from). Any missing requirements will need to be satisfied before proceeding or could result in errors, etc.

### Configuration

Now that cnf-testsuite is installed and prepared, we can now run CNF workloads and tests. We recommend installing and running a sample CNF to ensure cnf-testsuite is operational and set expectations of the output.

#### Configuring an example CNF

To use CoreDNS as an example CNF. Download the testsuite configuration to test CoreDNS:

- Make sure you are in your cnf-testsuite/ source repo checkout directory and do the following:
  ```
  curl -o cnf-testsuite.yml https://raw.githubusercontent.com/lfn-cnti/testsuite/main/example-cnfs/coredns/cnf-testsuite.yml
  ```
- Prepare the test suite to use the CNF by running:
  ```
  # via built binary
  ./cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml
  ```
  Or
  ```
  # via crystal
  crystal src/cnf-testsuite.cr cnf_install cnf-config=./cnf-testsuite.yml
  ```

There are other examples in the [example cnfs](example-cnfs) folder if you would like to test others.

#### NOTE: CNF **must** have a [helm chart](https://helm.sh/)

- To pass all current tests
- To support auto deployment of the CNF from the ([cnf-testsuite.yml](CNF_TESTSUITE_YML_USAGE.md)) configuration file.

### Running cnf-testsuite for the first time

#### Running Tests

If you want to run all tests for CoreDNS Example CNF, do the following (this is assuming your `cnf_install` ran without errors in the [configuration](#Configuring-an-example-CNF) steps:)
_For complete usage, see the [USAGE.md](USAGE.md) doc._

```
./cnf-testsuite all
```

The following will run only workload tests:

```
./cnf-testsuite workload
```

The following would run only the platform tests:

```
./cnf-testsuite platform
```

You can also run via `crystal` by replacing the `./cnf-testsuite` with `crystal spec src/cnf-testsuite.cr` and then the argument.

#### More Example Usage (also see the [complete usage documentation](https://github.com/lfn-cnti/testsuite/blob/main/USAGE.md))

```
# These assume you've already run the cnf_install pointing at a cnf-testsuite.yml config above. You can always specify your config at the end of each command as well, eg:
./cnf-testsuite all cnf-config=<path to your config yml>/cnf-testsuite.yml

# Runs all ga tests (generally available workload and platform tests)
./cnf-testsuite all

# Runs all alpha, beta and ga tests
./cnf-testsuite all alpha

# Runs all beta and ga tests
./cnf-testsuite all beta

# Run all wip, alpha, beta, and ga tests
./cnf-testsuite all wip

# Run all tests in the configureation lifecycle category
./cnf-testsuite configuration_lifecycle

# Run all tests in the installability
./cnf-testsuite installability
```

#### Checking Results

In the console where the test suite runs:

- PASSED or FAILED will be displayed for the tests

A test log file, eg. `cnf-testsuite-results-20201216.txt`, will be created which lists PASS or FAIL for every test based on the date.

For more details on points, see our [POINTS.md](./POINTS.md) documentation.

#### Uninstallation

Run the following to uninstall the CNF:

```
./cnf-testsuite cnf_uninstall
```

To also uninstall helper tools deployed by testsuite run `uninstall_all`.

_NOTE: CNF uninstallation does not handle manually deployed CNFs_

#### NOTE: If the OpenMetrics version changes, the protobuf file will need to be regenerated
```
git clone https://github.com/jeromegn/protobuf.cr
crystal build bin/protoc-gen-crystal.cr -o ~/bin/protoc-gen-crystal
git clone https://github.com/OpenObservability/OpenMetrics
cp ../protobuf.cr/openmetrics_data_model.pb.cr src/proto/ 
# You will need to install protobufs on your system e.g. sudo apt-get install -y protobuf-compiler
protoc -I.  --crystal_out . openmetrics_data_model.proto
```

### Ready to Bring Your Own CNF?

You can check out our [CNF_TESTSUITE_YML_USAGE.md](https://github.com/lfn-cnti/testsuite/blob/main/CNF_TESTSUITE_YML_USAGE.md) document on what is required to bring or use your own CNF.

- Follow the [INSTALL](INSTALL.md) or [SOURCE-INSTALL](SOURCE-INSTALL.md) to build the binary.
- Now head over to [CNF_TESTSUITE_YML_USAGE.md](https://github.com/lfn-cnti/testsuite/blob/main/CNF_TESTSUITE_YML_USAGE.md) for more detailed steps.
