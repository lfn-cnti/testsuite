# CNF Deployment Using Operators

## Overview

Operators are Kubernetes controllers that manage custom resources and automate application lifecycle tasks. When deploying CNFs (Cloud Native Network Functions) using operators, the test suite supports robust identification of resources created by operators, even when resources are created dynamically or indirectly.

## Resource Identification Strategies

1. **Label-based Identification**
   - The test suite fetches resources matching label selectors defined in `cnf-testsuite.yml` under `workload_resource_labels`.
   - After all deployments are installed, resources with these labels are identified and appended to the composite manifest (`installed_cnf_files/common-manifest.yml`).
   - This enables tests to reference resources reliably, regardless of when or how they are created by the operator.

2. **OwnerReference-based Identification**
   - Many operators create resources (e.g., Pods, ReplicaSets) with `ownerReferences` pointing to custom resources (CRDs) managed by the operator.
   - The test suite scans for resources owned by custom resources, using the `ownerReferences` field in Kubernetes metadata.
   - These owned resources are also appended to the composite manifest, ensuring that all relevant resources are tracked for testing.

## Example: Operator Deployment

Suppose an operator creates Pods either by labeling them or by setting `ownerReferences` to a custom resource (e.g., PodSet):

- **Labeled Pods:**
  - Pods are created with labels such as `cnf: my-operator`.
  - The test suite will identify these using the label selectors.

- **Owned Pods:**
  - Pods are created with `ownerReferences` pointing to a custom resource (e.g., `PodSet`).
  - The test suite will identify these by traversing owner references from custom resources.

## How the Test Suite Handles Operator Resources

- During installation, the suite waits for resources to become ready, using configurable timeouts.
- After installation, it fetches label-identified and ownerReference-identified resources and adds them to the manifest.
- Tests consume resources from the manifest, ensuring consistent and reliable test coverage even for dynamically created resources.

## Configuration

- **Label Selectors:**
  - Define label selectors in `cnf-testsuite.yml` under `workload_resource_labels`.
- **Timeouts:**
  - Use the `timeout` CLI argument or `CNF_TESTSUITE_LABEL_RESOURCE_SLEEP` environment variable to control waiting behavior for resource identification.

## Best Practices

- Ensure operator sets meaningful labels or ownerReferences on created resources.
- Use unique labels for each CNF to avoid conflicts.
- Review the composite manifest to verify all expected resources are included.
