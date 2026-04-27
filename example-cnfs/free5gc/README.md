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

## Initialize submodules

This example uses the free5GC Helm chart as a Git submodule.

After cloning the repository, initialize the submodule:

```bash
git submodule update --init --recursive
```

## Prepare CNTi test suite

Initialize the test suite:

```bash
cnf-testsuite setup
```

# Installation

Deploy free5GC using the CNTi test suite:

```bash
cnf-testsuite cnf_install cnf-config=example-cnfs/free5gc/cnf-testsuite.yml
```

The CNF is deployed into the `free5gc` namespace.

The free5GC Helm chart is located at:

`example-cnfs/free5gc/charts/free5gc-helm/charts/free5gc`

The chart is deployed automatically through the provided `cnf-testsuite.yml`.

# Running CNF Tests

To run the full CNTi test suite:

```bash
cnf-testsuite all
```

## Verify Deployment

To check that all components are running:

```bash
kubectl get pods -n free5gc
```

# Uninstallation

To uninstall free5GC:

```bash
cnf-testsuite cnf_uninstall cnf-config=example-cnfs/free5gc/cnf-testsuite.yml
```

In some cases, persistent resources (e.g. PersistentVolumeClaims) may remain and need to be removed manually:

```bash
kubectl delete pvc --all -n free5gc
```

# Notes and Adjustments

The free5GC Helm chart is included as an upstream Git submodule and is not modified directly.

To ensure compatibility with a kind-based Kubernetes environment, MongoDB configuration is overridden via the <br /> `cnf-testsuite.yml` file using Helm values.

The following adjustments are applied at deployment time:

- Disabled persistence (`mongodb.persistence.enabled=false`)
- Removed the `extraDeploy` section to avoid creation of a static PersistentVolume

These changes were necessary because the original chart assumes a specific storage backend (microk8s), which is not available in kind clusters.  
Without these modifications, MongoDB would remain in a `Pending` state due to incompatible storage configuration.

# Known Limitations

This example is intended as a **reference CNF deployment** for testing purposes and has several limitations:

- **Privileged networking requirements**
  - The UPF requires kernel-level networking features such as IP forwarding (`net.ipv4.ip_forward`, `net.ipv4.conf.all.forwarding`)
  - Without enabling these unsafe sysctls (e.g. via `allowedUnsafeSysctls` in kind), UPF pods fail to start with `SysctlForbidden` errors.

- **CNTi certification test results**
  - The following tests are observed to fail:

    - `non_root_containers`
      - Fails for UPF components (`iupf1`, `psaupf1`, `psaupf2`)
      - Reason: the UPF requires low-level networking capabilities and is designed to run with root privileges, which violates the non-root container requirement

    - `sig_term_handled`
      - Failed for multiple components
      - Reason: some pods were not ready during test execution, and free5GC containers do not consistently implement graceful shutdown via SIGTERM

- **Non-production configuration**
  - Persistence for MongoDB is disabled for compatibility with kind
  - The deployment is not optimized for high availability or data durability

- **Environment-specific behavior**
  - The setup is tested primarily on **kind clusters**
  - Other environments (e.g., managed Kubernetes services) may require additional adjustments

This example focuses on **deployability and testability**, not production readiness.