# What is [free5GC](https://www.free5gc.org/) 

Free5GC is an open-source implementation of a 5G Core Network (5GC).  
This example demonstrates how free5GC can be deployed as a Cloud-Native Network Function (CNF) using Helm and tested via the CNTi test suite.

The goal of this example is to provide a working reference deployment that is compatible with Kubernetes environments, including **kind clusters**.

---

# Architecture Overview

Free5GC implements a Service-Based Architecture (SBA) for 5G core networks, where individual network functions communicate over HTTP-based APIs.

The main components deployed in this example include:

- **NRF (Network Repository Function)** – service discovery
- **AMF (Access and Mobility Management Function)** – handles device registration and mobility
- **SMF (Session Management Function)** – manages sessions and IP allocation
- **UPF (User Plane Function)** – handles user data traffic forwarding
- **AUSF, UDM, UDR, PCF, NSSF** – supporting control-plane services

The **UPF component** has additional requirements compared to other network functions:
- It relies on low-level networking capabilities (packet forwarding, GTP tunneling)
- It requires kernel-level features such as IP forwarding

For this reason, when running in a Kubernetes environment (especially **kind**), specific `sysctl` settings must be enabled to allow proper packet routing and forwarding.

Without these settings, the UPF will fail to initialize or will not properly handle traffic.

# Prerequisites

- Kubernetes cluster (tested with **kind**)
- kubectl configured to access the cluster
- Helm installed
- CNTi test suite available locally

## kind cluster configuration (required for UPF)

When deploying on a kind cluster, the UPF component requires specific sysctl settings.

Save the following configuration as `kind-free5gc-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: KubeletConfiguration
    allowedUnsafeSysctls:
      - "net.ipv4.ip_forward"
      - "net.ipv4.conf.all.forwarding"
- role: worker
  kubeadmConfigPatches:
  - |
    kind: KubeletConfiguration
    allowedUnsafeSysctls:
      - "net.ipv4.ip_forward"
      - "net.ipv4.conf.all.forwarding"
- role: worker
  kubeadmConfigPatches:
  - |
    kind: KubeletConfiguration
    allowedUnsafeSysctls:
      - "net.ipv4.ip_forward"
      - "net.ipv4.conf.all.forwarding"

```
Create the kind cluster using the configuration file:


```bash
kind create cluster --config kind-free5gc-config.yaml
```

## Prepare CNTi test suite

Initialize the test suite:

```bash
cnf-testsuite setup
```

# Installation

Deploy free5GC using the CNTi test suite:

```bash
./cnf-testsuite cnf_install cnf-config=example-cnfs/free5gc/cnf-testsuite.yml
```

The CNF is deployed into the `free5gc` namespace.

This example uses the free5GC Helm chart located at:

`example-cnfs/free5gc/charts/free5gc`

The chart is deployed automatically through the provided `cnf-testsuite.yml`.

# Running CNF Tests

To run the full CNTi test suite:

```bash
./cnf-testsuite all
```

## Verify Deployment

To check that all components are running:

```bash
kubectl get pods -n free5gc
```

# Uninstallation

To uninstall free5GC:

```bash
./cnf-testsuite cnf_uninstall cnf-config=example-cnfs/free5gc/cnf-testsuite.yml
```

In some cases, persistent resources (e.g. PersistentVolumeClaims) may remain and need to be removed manually:

```bash
kubectl delete pvc --all -n free5gc
```

# Notes and Adjustments

The free5GC Helm chart was slightly modified to ensure compatibility with a kind-based Kubernetes environment.

The following changes were made to the MongoDB subchart (`charts/free5gc/charts/mongodb-15.6.0/values.yaml`):

- Removed the `extraDeploy` section that defined a static PersistentVolume with `microk8s-hostpath`
- Set `persistence.storageClass` to an empty value (`""`)
- Disabled persistence (`persistence.enabled=false`)

These changes were necessary because the original chart assumes a specific storage backend (microk8s), which is not available in kind clusters.  
Without these modifications, MongoDB would remain in a `Pending` state due to incompatible storage configuration.

The adjustments ensure that the deployment works with the default StorageClass provided by kind (typically `standard`).

Additionally, the following adjustments were made to container startup configuration:

- Removed the `/sbin/tini` entrypoint from multiple container deployments 
  (in various `*-deployment.yaml` templates)

This change simplifies container startup in the tested environment.

# Known Limitations

This example is intended as a **reference CNF deployment** for testing purposes and has several limitations:

- **Privileged networking requirements**
  - The UPF requires advanced networking capabilities (e.g., IP forwarding)
  - This may conflict with strict Kubernetes security policies

- **Potential CNTi test failures**
  - Some certification tests (e.g., related to privileged containers or security contexts) may fail due to the networking requirements of free5GC
  - These are expected and do not indicate a broken deployment

- **Non-production configuration**
  - Persistence for MongoDB is disabled for compatibility with kind
  - The deployment is not optimized for high availability or data durability

- **Environment-specific behavior**
  - The setup is tested primarily on **kind clusters**
  - Other environments (e.g., managed Kubernetes services) may require additional adjustments

This example focuses on **deployability and testability**, not production readiness.