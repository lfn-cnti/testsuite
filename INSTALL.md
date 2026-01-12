Installing the CNF Test Suite
---
### Overview
This INSTALL guide will detail the minimum requirements needed for cnf-testsuite while then providing installation with configuration steps to run the cnf-testsuite binary from both a binary installation and source installation method.

### Table of Contents
* [**Pre-Requisites**](#Pre-Requisites)
* [**Installation**](#Installation)
* [**Preparation**](#Preparation)
* [**Configuration**](#Configuration)
* [**Running cnf-testsuite for the first time**](#Running-cnf-testsuite-for-the-first-time)

### Pre-Requisites
This will detail the required minimum requirements needed in order to support cnf-testsuite.

#### Minimum Requirements
* **Kubernetes multi-node cluster** *(2 schedulable nodes minimum as a few tests require this. See [supported K8s and installation details](#Details-on-supported-k8s-clusters-and-installation) on installation.)*
* **containerd runtime** - for K8s cluster running the CNF to be tested
* **kubectl** *(run commands against K8s clusters, see [installing kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) for more details.)*
* **curl**
* **helm 3.8.2* *or newer* *(cnf-testsuite installs if not found locally)*
* **docker**  *(needed for the cni_compatibility test)*

#### Requirements for source installation
*Everything detailed in the [minimum requirements](https://hackmd.io/6h7NXdHnR4qUYgnnQPy5UA#Required) and the following:*
* **git** *(used to check out code from github)*
* **crystal-lang** version >=1.15.1 *(to compile the source and build the binary, see [crystal installation](https://crystal-lang.org/install/))*
* **shards** ([dependency manager](https://github.com/crystal-lang/shards) for crystal-lang)



---


#### Details on supported K8s clusters and installation:
<details><summary>Click here to drop down details</summary>

<p>

##### Supported K8s Clusters
- [Access](https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/) to a working [Certified K8s](https://cncf.io/ck) multi-node cluster via [KUBECONFIG environment variable](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/#set-the-kubeconfig-environment-variable). (See [K8s Getting started guide](https://kubernetes.io/docs/setup/) for options)
-  Follow the optional instructions below if you don't already have a K8s cluster setup
-  Minimum of 2 schedulable nodes as some tests will require more than one node to run.

##### Kind

- Follow the [kind install](KIND-INSTALL.md) instructions to setup a cluster in [kind](https://kind.sigs.k8s.io/).

##### AWS EKS

- [EKSCTL](https://eksctl.io/installation) can be used to create an AWS EKS cluster.

Sample manifest `testsuite-eksctl-manifest.yaml`:
``` yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: cnti-testsuite
  region: us-west-2
  version: "1.33"

addonsConfig:
  autoApplyPodIdentityAssociations: true

addons:
  - name: eks-pod-identity-agent
  - name: aws-ebs-csi-driver
    version: latest
    resolveConflicts: overwrite
    useDefaultPodIdentityAssociations: true
    configurationValues: |-
      defaultStorageClass:
        enabled: true

nodeGroups:
  - name: ng-1
    instanceType: m5.2xlarge
    amiFamily: AmazonLinux2023
    desiredCapacity: 4
```

To create the cluster, run:

``` bash
eksctl create cluster -f testsuite-eksctl-manifest.yaml
```

For more customization options and best practices, see the [EKS Cluster Creation User Guide](https://eksctl.io/usage/creating-and-managing-clusters/).
</p>
</details>



---


### Installation

We support the following methods of installing the cnf-testsuite:

- [Curl installation](#Curl-Binary-Installation) (via latest binary release)
- [Latest Binary](https://github.com/lfn-cnti/testsuite/releases/latest) (manual download)
- From [**Source**](#Source-Install) on github.


#### Curl Binary Installation

There are two methods to install via curl, we prefer the first method (the others including the manual and source install are optional):

- This first command using curl will download, install, and export the path automatically (recommended method):

```
source <(curl -s https://raw.githubusercontent.com/lfn-cnti/testsuite/main/curl_install.sh)
```

<details><summary>Click here for the alternate curl and manual install method</summary>
<p>

- The other curl method to download and install requires you to export the PATH to the location of the executable:
```
curl -s https://raw.githubusercontent.com/lfn-cnti/testsuite/main/curl_install.sh | bash
```

- The Latest Binary (or you can select a previous release if desired) can be pulled down with wget, curl or you're own preferred method. Once downloaded you'll need to make the binary executable and manually add to your path:
```
wget https://github.com/lfn-cnti/testsuite/releases/download/latest/latest.tar.gz
tar xzf latest.tar.gz
cd cnf-testsuite
chmod +x cnf-testsuite
export OLDPATH=$PATH; export PATH=$PATH:$(pwd)
```
</p>
</details>

#### Source Install

This is a brief summary for source installations and [does have requirements](#Requirements-for-source-installation) in order to compile a binary from source. To read more on source installation, see the [SOURCE-INSTALL](SOURCE_INSTALL.md) document.

<details><summary> Click here for brief source install details</summary>
<p>

Follow these steps to checkout the source from github and compile a cnf-testsuite binary:

```
git clone https://github.com/lfn-cnti/testsuite.git
cd cnf-testsuite/
shards install
crystal build src/cnf-testsuite.cr
```
This should build a cnf-testsuite binary in the root directory of the git repo clone.
</p>
</details>

### Preparation

Now that you have cnf-testsuite installed, we need to prepare the suite.

First make sure your K8s cluster is accessible (part of the [minimum pre-requisites](#Minimum-Requirements)). You can run the following to verify the cluster: 

```
kubectl cluster-info
```

And it should print a running kubernetes master in the output. Common kubectl errors and issues might relate to your KUBECONFIG variable. You can export to your K8s config by doing the following:

```
export KUBECONFIG=path/to/mycluster.config
```

*Note: We recommend running cnf-testsuite on a non-production cluster.*

The next step is to run the `setup` which prepares the cnf-testsuite. This runs pre-reqs to verify you have everything needed in order to run the suite, simply run the following:

```
cnf-testsuite setup
```

The test suite by default will pull docker images from https://docker.io. You can set your own username and password with local environment variables by doing the following:

```
export DOCKERHUB_USERNAME=<USERNAME>
export DOCKERHUB_PASSWORD=<PASSWORD>
```

Please refer to the [CNF_TESTSUITE_YML_USAGE.md](CNF_TESTSUITE_YML_USAGE.md#Using-a-Private-Registry) for details on using a private registry.


<details><summary>Install Tab Completion for cnf-testsuite (Optional)</summary>

Check out our (experimental) support for tab completion!

NOTE: also compatible with the installation styles from kubectl completion install if you prefer
https://kubernetes.io/docs/tasks/tools/install-kubectl/#enable-kubectl-autocompletion

```
cnf-testsuite completion -l error > test.sh
source test.sh
```
</details>

### Configuration
Now cnf-testsuite is prepared, we're ready to configure it to point at a CNF to test.

#### Using an Example CNF

- If you want to use an example CNF, you can download our CoreDNS example CNF by doing the following:

```
wget -O cnf-testsuite.yml https://raw.githubusercontent.com/lfn-cnti/testsuite/main/example-cnfs/coredns/cnf-testsuite.yml
```
- The wget gets a working config file, now tell cnf-testsuite to use it by doing the following:
```
cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml
```

- There are other examples in the [examples-cnfs](https://github.com/lfn-cnti/testsuite/tree/master/example-cnfs) directory that can be used for testing as well.

#### Bring Your Own CNF

If you've brought your own CNF to test, review the [CNF_TESTSUITE_YML_USAGE.md](CNF_TESTSUITE_YML_USAGE.md) document on formatting and other requirements.

If you've followed the [CNF_TESTSUITE_YML_USAGE.md](CNF_TESTSUITE_YML_USAGE.md) guide and have your cnf-testsuite.yml ready, you can run the same command we ran for the example CNF to set it up:

```
cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml
```

### Running cnf-testsuite for the first time

#### Running Tests

If you want to run all tests, do the following (this is assuming your `cnf_install` ran without errors in the [configuration](#Configuration) steps:)
_For complete usage, see the [USAGE.md](USAGE.md) doc._

```
cnf-testsuite all
```

The following will run only workload tests:
```
cnf-testsuite workload 
```

The following would run only the platform tests:
```
cnf-testsuite platform 
```

#### Checking Results

In the console where the test suite runs:
- PASSED or FAILED will be displayed for the tests

A test log file, eg. `cnf-testsuite-results-20201216.txt`, will be created which lists PASS or FAIL for every test based on the date.

For more details on points, see our [POINTS.md](./POINTS.md) documentation.

#### Uninstallation

Run the following to uninstall the CNF (this is assuming you installed the cnf-testsuite.yml in your present working directory):
```
cnf-testsuite cnf_uninstall
```

To also uninstall helper tools deployed by testsuite run `uninstall_all`.

_NOTE: CNF uninstallation does not handle manually deployed CNFs_
