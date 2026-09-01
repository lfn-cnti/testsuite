# What is [Linkerd](https://linkerd.io/)?

Linkerd is a service mesh, designed to give platform-wide observability, reliability, and security without requiring configuration or code changes.

## Pre-req:

Follow [Pre-req steps](../../INSTALL.md#pre-requisites), including
Set the KUBECONFIG environment to point to the remote K8s cluster

### Automated Linkerd installation

Run cnti-testsuite setup

```
./cnti-testsuite setup
```

Install linkerd

```
./linkerd_install.sh

helm repo add linkerd https://helm.linkerd.io/stable

helm install linkerd-crds linkerd/linkerd-crds -n linkerd --create-namespace 

.cnti-testsuite cnf_install cnf-path=example-cnfs/linkerd2/cnti-testsuite.yaml
```

Run the test suite:

```
./cnti-testsuite all
```

linkerd uninstallation

```
./cnti-testsuite cnf_uninstall
```
