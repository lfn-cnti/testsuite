# What is [CoreDNS](https://coredns.io/)

CoreDNS is a DNS server/forwarder, written in Go, that chains plugins. Each plugin performs a (DNS) function.

DNS is a critical network function that can be found in many Telecom use cases such as the vCPE.

CoreDNS can listen for DNS requests coming in over UDP/TCP, TLS (RFC 7858), also called DoT, DNS over HTTP/2 - DoH - (RFC 8484) and gRPC (not a standard).

# Prerequistes

Follow [Pre-req steps](../../INSTALL.md#pre-requisites), including

- Set the KUBECONFIG environment to point to the remote K8s cluster
- Downloading the binary cnti-testsuite release

### Automated CNF installation

Initialize the test suite

```
./cnti-testsuite setup
```

Configure and deploy CoreDNS as the target CNF

```
./cnti-testsuite cnf_install cnf-path=example-cnfs/coredns/cnti-testsuite.yaml
```

Run the all the tests

```
./cnti-testsuite all
```

Check the results file

Uninstall the CNF (including undeployment of CoreDNS)

```
./cnti-testsuite cnf_uninstall
```
