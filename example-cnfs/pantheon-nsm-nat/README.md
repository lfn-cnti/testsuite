# What is [Pantheon NSM NAT](https://github.com/PANTHEONtech/cnf-examples/tree/master/nsm/LFNWebinar)

In this simple example we demonstrate the capabilities of the NSM agent - a control-plane for Cloud-native Network Functions deployed in Kubernetes cluster. The NSM agent seamlessly integrates Ligato framework for Linux and VPP network configuration management together with Network Service Mesh (NSM) for separation of data plane from control plane connectivity between containers and external endpoints.

In the presented use-case we simulate scenario in which a client from a local network needs to access a web server with a public IP address. The necessary Network Address Translation (NAT) is performed in-between the client and the web server by the high-performance VPP NAT plugin, deployed as a true CNF (Cloud-Native Network Functions) inside a container. For simplicity the client is represented by a K8s Pod running image with cURL installed (as opposed to being an external endpoint as it would be in a real-world scenario). For the server side the minimalistic TestHTTPServer implemented in VPP is utilized.

In all the three Pods an instance of NSM Agent is run to communicate with the NSM manager via NSM SDK and negotiate additional network connections to connect the pods into a chain client <-> NAT-CNF <-> web-server (see diagrams below). The agents then use the features of Ligato framework to further configure Linux and VPP networking around the additional interfaces provided by NSM (e.g. routes, NAT).

The configuration to apply is described declaratively and submitted to NSM agents in a Kubernetes native way through our own Custom Resource called CNFConfiguration. The controller for this CRD (installed by cnf-crd.yaml) simply reflects the content of applied CRD instances into an etcd datastore from which it is read by NSM agents. For example, the configuration for the NSM agent managing the central NAT CNF can be found in cnf-nat44.yaml.

More information about cloud-native tools and network functions provided by PANTHEON.tech can be found on our website cdnf.io.

# Prerequistes

Follow [Pre-req steps](../../INSTALL.md#pre-requisites), including

- Set the KUBECONFIG environment to point to the remote K8s cluster
- Downloading the binary cnti-testsuite release

### Automated CNF installation

Initialize the test suite

```
./cnti-testsuite setup
```

Configure and deploy nsm and nsm-nat as the target CNF

```
./cnti-testsuite cnf_install --cnf-config ./example-cnfs/nsm/cnti-testsuite.yaml

./cnti-testsuite cnf_install --cnf-config ./example-cnfs/pantheon-nsm-nat/cnti-testsuite.yaml
```

Run the all the tests

```
./cnti-testsuite all
```

Check the results file

Uninstall the CNF (including undeployment of nsm-nat)

```
./cnti-testsuite cnf_uninstall
```
