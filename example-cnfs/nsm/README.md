# What is [NSM](https://https://networkservicemesh.io//)

Network Service Mesh (NSM) is a novel approach solving complicated L2/L3 use cases in Kubernetes that are tricky to address with the existing Kubernetes Network Model. Inspired by Istio, Network Service Mesh maps the concept of a Service Mesh to L2/L3 payloads as part of an attempt to re-imagine NFV in a Cloud-native way.

# Prerequistes

Follow [Pre-req steps](../../INSTALL.md#pre-requisites), including

- Set the KUBECONFIG environment to point to the remote K8s cluster
- Downloading the binary cnf-testsuite release

### Automated CNF installation

Initialize the test suite

```
./cnf-testsuite setup
```

Configure and deploy NSM as the target CNF

```
./cnf-testsuite cnf_install --cnf-config ./example-cnfs/nsm/cnf-testsuite.yml
```

Run the all the tests

```
./cnf-testsuite all
```

Check the results file

Uninstall the CNF (including undeployment of NSM)

```
./cnf-testsuite cnf_uninstall
```
