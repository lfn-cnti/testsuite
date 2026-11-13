# CNTi Test Suite test documentation

## Table of Contents

* [**Test types**](#test-types): the Essential and Bonus tests

* [**Category: Compatibility, Installability and Upgradability Tests**](#category-compatibility-installability-and-upgradability-tests)

   [[Increase decrease capacity]](#increase-decrease-capacity) | [[Helm chart published]](#helm-chart-published) | [[Helm chart valid]](#helm-chart-valid) | [[Helm deploy]](#helm-deploy) | [[Rollback]](#rollback) | [[Rolling version change]](#rolling-version-change) | [[Rolling update]](#rolling-update) | [[Rolling downgrade]](#rolling-downgrade) | [[CNI compatible]](#cni-compatible) | [[Deprecated K8s Features]](#deprecated-k8s-features) | [[Dual stack]](#dual-stack)

* [**Category: Microservice Tests**](#category-microservice-tests)

   [[Reasonable Image Size]](#reasonable-image-size) | [[Reasonable Startup Time]](#reasonable-startup-time) | [[Single Process Type in One Container]](#single-process-type-in-one-container) | [[Service Discovery]](#service-discovery) | [[Shared Database]](#shared-database) | [[Specialized Init Systems]](#specialized-init-systems) | [[System Init Not Used]](#system-init-not-used) | [[Sigterm Handled]](#sigterm-handled) | [[Zombie Handled]](#zombie-handled)

* [**Category: State Tests**](#category-state-tests)

   [[Node drain]](#node-drain) | [[No local volume configuration]](#no-local-volume-configuration) | [[Elastic volumes]](#elastic-volumes) | [[Database persistence]](#database-persistence)

* [**Category: Reliability, Resilience and Availability Tests**](#category-reliability-resilience-and-availability-tests)

   [[CNF under network latency]](#cnf-under-network-latency) | [[CNF with host disk fill]](#cnf-with-host-disk-fill) | [[Pod delete]](#pod-delete) | [[Memory hog]](#memory-hog) | [[IO Stress]](#io-stress) | [[Network corruption]](#network-corruption) | [[Network duplication]](#network-duplication) | [[Pod DNS errors]](#pod-dns-errors) | [[Liveness probe]](#liveness-probe) | [[Readiness probe]](#readiness-probe) | [[Startup probe]](#startup-probe) | [[Pod owner]](#pod-owner)

* [**Category: Observability and Diagnostic Tests**](#category-observability-and-diagnostic-tests)

   [[Use stdout/stderr for logs]](#use-stdoutstderr-for-logs) | [[Prometheus installed]](#prometheus-installed) | [[Routed logs]](#routed-logs) | [[OpenMetrics compatible]](#openmetrics-compatible) | [[Jaeger tracing]](#jaeger-tracing) | [[Termination message policy]](#termination-message-policy)

* [**Category: Security Tests**](#category-security-tests)

   [[Container socket mounts]](#container-socket-mounts) | [[Privileged Containers]](#privileged-containers) | [[External IPs]](#external-ips) | [[SELinux Options]](#selinux-options) | [[Sysctls]](#sysctls) | [[Privilege escalation]](#privilege-escalation) | [[Seccomp profile]](#seccomp-profile) | [[Symlink file system]](#symlink-file-system) | [[Application credentials]](#application-credentials) | [[Host network]](#host-network) | [[Service account mapping]](#service-account-mapping) | [[Dedicated service account]](#dedicated-service-account) | [[Ingress and Egress blocked]](#ingress-and-egress-blocked) | [[Insecure capabilities]](#insecure-capabilities) | [[Non-root containers]](#non-root-containers) | [[Host PID/IPC privileges]](#host-pidipc-privileges) | [[Linux hardening]](#linux-hardening) | [[CPU limits]](#cpu-limits) | [[Memory limits]](#memory-limits) | [[Resource requests]](#resource-requests) | [[Init container requests]](#init-container-requests) | [[Immutable File Systems]](#immutable-file-systems) | [[HostPath Mounts]](#hostpath-mounts) | [[SBOM available]](#sbom-available)

* [**Category: Configuration Tests**](#category-configuration-tests)

   [[Default namespaces]](#default-namespaces) | [[Latest tag]](#latest-tag) | [[Require labels]](#require-labels) | [[Versioned tag]](#versioned-tag) | [[NodePort not used]](#nodeport-not-used) | [[HostPort not used]](#hostport-not-used) | [[Hardcoded IP addresses in K8s runtime configuration]](#hardcoded-ip-addresses-in-k8s-runtime-configuration) | [[Secrets used]](#secrets-used) | [[Immutable configmap]](#immutable-configmap) | [[Kubernetes Alpha APIs]](#kubernetes-alpha-apis) | [[Operator installed]](#operator-installed) | [[Hugepages volumes]](#hugepages-volumes) | [[Exclusive CPUs]](#exclusive-cpus)

* [**Common rules**](#common-rules)

   [[Rollout tests]](#rollout-tests) | [[Containers that cannot be inspected]](#containers-that-cannot-be-inspected) | [[Chaos tests]](#chaos-tests) | [[Jobs and CronJobs]](#jobs-and-cronjobs)

----------

## Test types

Every test is Essential, Normal or Bonus, as the suite's code declares it. A passed test scores 100 points when it is Essential, 5 when Normal and 1 when Bonus; a failed one scores 0, except [Database persistence](#database-persistence), which scores −1. The Essential tests are the ones `./cnti-testsuite essential` runs, the set the CNTi essential badge counts. A test not listed below is Normal.

**Essential** (19 tests):

| Test | Category | Command |
| --- | --- | --- |
| [Increase decrease capacity](#increase-decrease-capacity) | Compatibility | `increase_decrease_capacity` |
| [Single Process Type in One Container](#single-process-type-in-one-container) | Microservice | `single_process_type` |
| [Specialized Init Systems](#specialized-init-systems) | Microservice | `specialized_init_system` |
| [Sigterm Handled](#sigterm-handled) | Microservice | `sig_term_handled` |
| [Zombie Handled](#zombie-handled) | Microservice | `zombie_handled` |
| [Node drain](#node-drain) | State | `node_drain` |
| [Liveness probe](#liveness-probe) | Reliability | `liveness` |
| [Readiness probe](#readiness-probe) | Reliability | `readiness` |
| [Use stdout/stderr for logs](#use-stdoutstderr-for-logs) | Observability | `log_output` |
| [Container socket mounts](#container-socket-mounts) | Security | `container_sock_mounts` |
| [Privileged Containers](#privileged-containers) | Security | `privileged_containers` |
| [SELinux Options](#selinux-options) | Security | `selinux_options` |
| [Non-root containers](#non-root-containers) | Security | `non_root_containers` |
| [CPU limits](#cpu-limits) | Security | `cpu_limits` |
| [Memory limits](#memory-limits) | Security | `memory_limits` |
| [HostPath Mounts](#hostpath-mounts) | Security | `hostpath_mounts` |
| [Latest tag](#latest-tag) | Configuration | `latest_tag` |
| [HostPort not used](#hostport-not-used) | Configuration | `hostport_not_used` |
| [Hardcoded IP addresses in K8s runtime configuration](#hardcoded-ip-addresses-in-k8s-runtime-configuration) | Configuration | `hardcoded_ip_addresses_in_k8s_runtime_configuration` |

**Bonus** (21 tests):

| Test | Category | Command |
| --- | --- | --- |
| [Dual stack](#dual-stack) | Compatibility | `dual_stack` |
| [Reasonable Image Size](#reasonable-image-size) | Microservice | `reasonable_image_size` |
| [Service Discovery](#service-discovery) | Microservice | `service_discovery` |
| [No local volume configuration](#no-local-volume-configuration) | State | `no_local_volume_configuration` |
| [Elastic volumes](#elastic-volumes) | State | `elastic_volumes` |
| [CNF under network latency](#cnf-under-network-latency) | Reliability | `pod_network_latency` |
| [IO Stress](#io-stress) | Reliability | `pod_io_stress` |
| [Network corruption](#network-corruption) | Reliability | `pod_network_corruption` |
| [Network duplication](#network-duplication) | Reliability | `pod_network_duplication` |
| [Startup probe](#startup-probe) | Reliability | `startup_probe` |
| [Prometheus installed](#prometheus-installed) | Observability | `prometheus_traffic` |
| [Routed logs](#routed-logs) | Observability | `routed_logs` |
| [OpenMetrics compatible](#openmetrics-compatible) | Observability | `open_metrics` |
| [Jaeger tracing](#jaeger-tracing) | Observability | `tracing` |
| [Termination message policy](#termination-message-policy) | Observability | `termination_message_policy` |
| [Ingress and Egress blocked](#ingress-and-egress-blocked) | Security | `ingress_egress_blocked` |
| [Linux hardening](#linux-hardening) | Security | `linux_hardening` |
| [Immutable File Systems](#immutable-file-systems) | Security | `immutable_file_systems` |
| [Secrets used](#secrets-used) | Configuration | `secrets_used` |
| [Immutable configmap](#immutable-configmap) | Configuration | `immutable_configmap` |
| [Operator installed](#operator-installed) | Configuration | `operator_installed` |

----------

## Category: Compatibility, Installability and Upgradability Tests

CNFs should work with any Certified Kubernetes product and any CNI-compatible network that meet their functionality requirements. The CNTI Test Suite will check for usage of standard, in-band deployment tools such as Helm (version 3) charts. The CNTI Test Suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s [kubectl](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources).

Service providers have historically had issues with the installability of vendor network functions. This category tests the installability and lifecycle management (the create, update, and delete of network applications) against widely used K8s installation solutions such as Helm.

### Usage

All compatibility: `./cnti-testsuite compatibility`

----------

### Increase decrease capacity

#### Overview

Scales each running Deployment and StatefulSet up by two replicas and back to its deployed count, then deletes one pod of each of them, of every DaemonSet and of every single-instance Deployment at once, and checks that each is Ready again. The restart shows a clustered workload that lost members while scaling down.
Expectation: The number of replicas for a Pod increases and then decreases, and the CNF still starts its pods afterwards.

#### Rationale

A CNF should be able to increase and decrease its capacity without running into errors.

HPA (horizontal pod autoscale) will autoscale replicas to accommodate when there is an increase of CPU, memory or other configured metrics to prevent disruption by allowing more requests
by balancing out the utilisation across all of the pods.
Decreasing replicas works the same as increase but rather scale down the number of replicas when the traffic decreases to the number of pods that can handle the requests.
You can read more about it in [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) and in the [K8s scaling cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources).

#### Remediation

Check out the kubectl docs for how to [manually scale your cnf.](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources)
Also here is some info about [things that could cause failures.](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#failed-deployment)

#### Usage

`./cnti-testsuite increase_decrease_capacity`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: Deployments and StatefulSets are scaled from their deployed replica count up by two, then back to it. A DaemonSet runs one pod per node and has no replica count to scale: it is named in the details and judged by the restart alone, one pod deleted and the DaemonSet Ready again on every node it is scheduled for, so a per-node workload (a router, a CNI, a node agent) earns the point for what it can do. A Deployment the chart runs with one replica and `strategy: Recreate` is taken as single-instance: Recreate does not limit the replica count, but it is how a chart says that a pod must never run beside its replacement (a single identity such as a gNB-DU or an IMSI, or a volume only one pod can mount), so the test does not scale it: it is named in the details and judged by the same restart, one pod deleted and the Deployment Ready again. A workload deployed with zero replicas runs nothing to scale and is only named in the details.
* **Configuration**: `CNTI_TESTSUITE_POD_READINESS_TIMEOUT`: after the restart, every workload must be Ready again within twice this timeout, as the CNF's start-up dependencies resolve one after another.
* **Verdicts**: scaling back restores the replica counts, not the application's state: a clustered StatefulSet (a database replica set, a quorum) can keep the members it lost and stay degraded, which shows only when a pod has to start again. So once every scaled workload is back at its count, one pod of each is deleted, together with the pods of the DaemonSets and single-instance Deployments, all at the same time, and a workload that is not Ready again in time fails the test, with the reason in the details. When a workload fails to scale, the scaled workloads are not restarted; an operator-owned workload that does not follow the scale is named, not failed, and does not stop the restart. A workload whose controller owner is an operator's custom resource takes its size from that resource: it is scaled like the others, and if it does not follow the direct change (the operator reverts it, or never configures pods it did not ask for) it is named in the details instead of failing the CNF; the test moves on as soon as the replica count is set back, without waiting out the timeout. The test is not applicable when every workload has zero replicas (or is a DaemonSet scheduled on no node), or is operator-sized with none following, and skipped when the CNF has no Deployment, StatefulSet or DaemonSet at all. A DaemonSet is judged by the nodes its controller reports it runs on; one whose controller reports nothing within `CNTI_TESTSUITE_GENERIC_OPERATION_TIMEOUT` (pods already bound to a node count meanwhile) is named in the details and not judged, and the test is skipped when it leaves nothing else to judge.
* **Side effects**: the replica counts change, and one pod is deleted from each workload the restart judges (see Verdicts): not from a workload with zero replicas, a DaemonSet scheduled on no node, an operator-owned workload that did not follow the scale, or the scaled workloads when a scale failed. Every workload ends back at its deployed count.

</details>

----------

### Helm chart published

#### Overview

Looks every Helm chart of the CNF up in its repository with [`helm search`](https://helm.sh/docs/helm/helm_search_repo/) and reports, per chart, the repository searched and the version found or the reason nothing was; a chart the repository does not know is a finding. Charts pulled from an OCI registry are published by construction. N/A when the CNF has no Helm chart deployment.
Expectation: The Helm chart is published in a Helm Repository.

#### Rationale

If a helm chart is published, it is significantly easier to install for the end user.
The management and versioning of the helm chart are handled by the helm registry and client tools
rather than manually as directly referencing the helm chart source.

Sources: [Helm chart best practices](https://helm.sh/docs/chart_best_practices/).

#### Remediation

Make sure your CNF helm charts are published in a Helm Repository.

#### Usage

`./cnti-testsuite helm_chart_published`

----------

### Helm chart valid

#### Overview

Runs [`helm lint`](https://helm.sh/docs/helm/helm_lint/) on every chart and chart directory of the CNF, with the values files the CNF installs with, and reports each chart's lint result; a failing chart is a finding with its first error. N/A when the CNF has no Helm chart deployment.
Expectation: No syntax or validation problems are found in the chart.

#### Rationale

A chart should pass the [lint specification](https://helm.sh/docs/helm/helm_lint/#helm)

Sources: [Helm chart best practices](https://helm.sh/docs/chart_best_practices/); [ETSI NFV, Helm charts as the CNF package (NFV-SOL 004/018)](https://www.etsi.org/technologies/nfv).

#### Remediation

Make sure your helm charts pass lint tests.

#### Usage

`./cnti-testsuite helm_chart_valid`

----------

### Helm deploy

#### Overview

Checks that every Helm deployment declared in `cnti-testsuite.yaml` exists in the cluster as a deployed Helm release, under the name and namespace the installer gave it; the chart, version and status of each release are reported. A CNF installed from manifests only is not applicable.
Expectation: Every Helm deployment of the CNF is a deployed Helm release.

#### Rationale

A helm chart should be [deployable to a cluster](https://helm.sh/docs/helm/helm_install/#helm)

Sources: [ETSI NFV, Helm charts as the CNF package (NFV-SOL 004/018)](https://www.etsi.org/technologies/nfv); [Helm chart best practices](https://helm.sh/docs/chart_best_practices/).

#### Remediation

Make sure your helm charts are valid and can be deployed to clusters.

#### Usage

`./cnti-testsuite helm_deploy`

----------

### Rollback

#### Overview

Checks that a version change can be undone: the CNF is moved to the version before the installed one, then rolled back to the installed one with `helm rollback` or [kubectl rollout undo](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout), and every workload must roll out within the timeout.
Expectation: The CNF Software version can be successfully incremented, then rolled back.

#### Rationale

K8s best practice is to allow [K8s to manage the rolling back](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment) of an application resource instead of having operators manually rolling back the resource by using something like blue/green deploys.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

For a chart installed from a Helm repository or an OCI registry, ensure that the release, moved to its previous chart version with `helm upgrade`, can be rolled back to the installed revision with `helm rollback` and that every workload rolls out again. For workloads from a chart directory or manifests, ensure that you can upgrade your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command, then rollback the upgrade using the [Kubectl Rollout Undo](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout) command. A workload whose undo kubectl refuses is a finding with kubectl's reason; `spec.revisionHistoryLimit: 0` keeps no revision to return to ("no rollout history found"), so set it to 1 or more (the default is 10).

#### Usage

`./cnti-testsuite rollback`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: Deployments, StatefulSets and DaemonSets, as a Helm release (`helm_charts`) or one container image at a time; Jobs and CronJobs are not applicable.
* **Configuration**: `previous_chart_version` for a release; `rollback_from_tag` per container in `container_names`.
* **Verdicts**: a release is moved to its previous chart version with `helm upgrade`, without judging that move, then rolled back to the installed revision with `helm rollback`; that rollback is judged: every workload of the release must roll out within the timeout. A release whose previous version cannot be installed is named in the details and not judged, since no rollback needs a downgrade. A container is moved to its previous image with kubectl set image and rolled back with kubectl rollout undo; a workload whose undo kubectl refuses is a finding with kubectl's reason (`spec.revisionHistoryLimit: 0` keeps no revision to return to). A rollout that does not complete is reported per resource with the image and the reason.
* **Side effects**: the release is brought back to the installed version afterwards; the undo returns each workload to its deployed image, and when kubectl refuses the undo the deployed image is set back directly.
* **Common rules**: [Rollout tests](#rollout-tests) (the previous version, what is left out, version skew, operator-owned workloads), [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Rolling version change

#### Overview

Checks that the CNF can change its version in place and return to the installed one: it is moved to the version before the installed one and back, and every workload must roll out within the timeout. A chart from a repository is moved as a Helm release; other workloads have each container's image changed with [kubectl set image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-).
Expectation: The CNF Software version is successfully rolled back to its original version.

#### Rationale

(update, version change, downgrade): K8s best practice for version/installation management (lifecycle management) of applications is to have [K8s track the version of the manifest information](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment) for the resource (deployment, pod, etc) internally.
Whenever a rollback is needed the resource will have the exact manifest information that was tied to the application when it was deployed.
This adheres the principles driving immutable infrastructure and declarative specifications.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

For a chart installed from a Helm repository or an OCI registry, ensure that the release can be upgraded from its previous chart version back to the installed one with `helm upgrade`, every workload rolling out. For workloads from a chart directory or manifests, ensure that you can successfully rollback the software version of your CNF by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnti-testsuite rolling_version_change`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: Deployments, StatefulSets and DaemonSets, as a Helm release (`helm_charts`) or one container image at a time; Jobs and CronJobs are not applicable.
* **Configuration**: `previous_chart_version` for a release; `rolling_version_change_test_tag` per container in `container_names`.
* **Verdicts**: a release is moved to its previous chart version with `helm upgrade`, without judging that move, then upgraded back to the installed version; that upgrade is judged: every workload of the release must roll out within the timeout. A release whose previous version cannot be installed is named in the details and not judged, since no upgrade needs a downgrade. A container's rollout to its previous image must complete within the timeout; one that does not is reported per resource with the image and the reason.
* **Side effects**: the release is brought back to the installed version, and the images the test changed are restored as described in [Rollout tests](#rollout-tests); a workload that does not come back is a finding of this test.
* **Common rules**: [Rollout tests](#rollout-tests) (the previous version, what is left out, version skew, operator-owned workloads), [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Rolling update

#### Overview

Checks that the CNF can be upgraded in place: it is moved to the version before the installed one and upgraded back, and every workload must roll out within the timeout. A chart from a repository is moved as a Helm release; other workloads have each container's image changed with [kubectl set image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-).
Expectation: The CNF Software version can be successfully incremented.

#### Rationale

See rolling version change.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

For a chart installed from a Helm repository or an OCI registry, ensure that the release can be upgraded from its previous chart version to the installed one with `helm upgrade`, every workload rolling out. For workloads from a chart directory or manifests, ensure that you can successfully perform a rolling upgrade of your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnti-testsuite rolling_update`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: Deployments, StatefulSets and DaemonSets, as a Helm release (`helm_charts`) or one container image at a time; Jobs and CronJobs are not applicable.
* **Configuration**: `previous_chart_version` for a release; `rolling_update_test_tag` per container in `container_names`.
* **Verdicts**: a release is moved to its previous chart version with `helm upgrade`, without judging that move, then upgraded back to the installed version; that upgrade is judged: every workload of the release must roll out within the timeout. A release whose previous version cannot be installed is named in the details and not judged, since no upgrade needs a downgrade. A container's rollout to its previous image must complete within the timeout; one that does not is reported per resource with the image and the reason.
* **Side effects**: the release is brought back to the installed version, and the images the test changed are restored as described in [Rollout tests](#rollout-tests); a workload that does not come back is a finding of this test.
* **Common rules**: [Rollout tests](#rollout-tests) (the previous version, what is left out, version skew, operator-owned workloads), [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Rolling downgrade

#### Overview

Checks that the CNF can be downgraded in place: it is moved to the version before the installed one, and every workload must roll out within the timeout. A chart from a repository is moved as a Helm release; other workloads have each container's image changed with [kubectl set image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-). The CNF is put back to the installed version afterwards.
Expectation: The CNF Software version is successfully downgraded to a software version older than the original installation version.

#### Rationale

See rolling version change.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

For a chart installed from a Helm repository or an OCI registry, ensure that the release can be moved down to its previous chart version with `helm upgrade`, every workload rolling out. For workloads from a chart directory or manifests, ensure that you can successfully change the software version of your CNF back to an older version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnti-testsuite rolling_downgrade`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: Deployments, StatefulSets and DaemonSets, as a Helm release (`helm_charts`) or one container image at a time; Jobs and CronJobs are not applicable.
* **Configuration**: `previous_chart_version` for a release; `rolling_downgrade_test_tag` per container in `container_names`.
* **Verdicts**: a release is moved down to its previous chart version with `helm upgrade`, and that move is judged: every workload of the release must roll out within the timeout, and a release that cannot be moved down is a failure. A container's rollout to its previous image must complete within the timeout; one that does not is reported per resource with the image and the reason.
* **Side effects**: the release is brought back to the installed version, and the images the test changed are restored as described in [Rollout tests](#rollout-tests); a workload that does not come back is a finding of this test.
* **Common rules**: [Rollout tests](#rollout-tests) (the previous version, what is left out, version skew, operator-owned workloads), [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### CNI compatible

#### Overview

This statically inspects the CNF's rendered manifests for features that couple it to one specific CNI plugin: Multus `NetworkAttachmentDefinition` objects, `k8s.v1.cni.cncf.io/networks` annotations requesting extra networks, Calico- or Cilium-specific APIs and annotations, and SR-IOV device resource requests.
Expectation: the CNF requests nothing that only one specific CNI plugin can provide

#### Rationale

A CNF should be runnable by any CNI that adheres to the [CNI specification](https://github.com/containernetworking/cni/blob/master/SPEC.md); manifests that hardwire vendor-specific network features only run on matching clusters.

Sources: [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Avoid vendor-specific network APIs, annotations and device resources in the CNF's manifests, or isolate them behind optional, documented configuration.

#### Usage

`./cnti-testsuite cni_compatible`

----------

### Deprecated K8s Features

#### Overview

Checks that the CNF uses no deprecated Kubernetes API version, annotation or field. The cluster's API server decides what is deprecated: the CNF's manifests are sent to it as a dry-run, which changes nothing, and each deprecation warning it returns is reported, with the resource that carries it when the warning identifies one. Any such warning fails the test.
Expectation: The CNF uses no API version, annotation or field that the cluster's API server reports as deprecated.

#### Rationale

A CNF should avoid using any deprecated features that are scheduled for removal. It should transition to stable and
actively maintained alternatives.

Sources: [Kubernetes API deprecation policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Ensure that the CNF is not using deprecated Kubernetes features. If any are detected, follow tips from warning message displayed by testsuite and/or consult [Deprecated API Migration Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/).

#### Usage

`./cnti-testsuite deprecated_k8s_features`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every object of the CNF's installed manifest. What the CNF ships (its charts and manifests, custom resources included) is judged as such. The objects an operator created for the CNF's custom resources, the ones `workload_resource_labels` selects and the CRDs discovered behind its custom resources are copies read back from the cluster: they are judged without the fields the server assigned them (`status`, `uid`, `resourceVersion`, `creationTimestamp`, `generation`, `managedFields`), for a deprecated field or annotation they carry.
* **Verdicts**: each part is dry-run on the server twice, as a server-side apply and as a create, and the warnings of both are joined: the API server gives some warnings only on create (the Ingress `kubernetes.io/ingress.class` annotation, for one) and does not repeat them when an installed object is re-applied unchanged. A warning counts when the word "deprecated" stands on its own in it, so a resource whose name contains the word is not a finding. Any such warning fails the test. Each warning is listed; one that names an API version and kind is attributed to the CNF's resources of that version and kind, one that names an annotation to the resources that carry it, and one about a field is listed without a resource.
* **Verdicts**: the test is skipped when the CNF's manifest is not there (the CNF is not installed), and when the server-side apply of what the CNF ships fails and no deprecation warning was found at all, with the API server's error as the reason; when warnings were found, the test fails whatever the dry-run returned. A read-back copy that fails to dry-run says nothing about the CNF (a create of an object that exists is refused, after its warnings) and is not held against it.
* **Side effects**: none: every request is a dry-run, and nothing in the cluster is created or changed.
* **Limits**: the API server reports what is deprecated in the Kubernetes version the cluster runs; a version deprecated only in a later release is not found. A read-back copy comes back in the server's preferred API version, so the API version an operator chose when it created the object is not visible and not judged.

</details>

----------

### Dual stack

#### Overview

Checks that each of the CNF's Services declares dual-stack, with `spec.ipFamilyPolicy` set to `PreferDualStack` or `RequireDualStack`. A Service left single-stack fails: on a dual-stack cluster it receives only the cluster's primary address family. The test checks the declaration only, not that the CNF works over IPv6.
Expectation: Every Service of the CNF, other than an `ExternalName` one, declares dual-stack, with `PreferDualStack` or `RequireDualStack`.

#### Rationale

[Anuket RA2 inf.ntw.04](https://cntt.readthedocs.io/projects/ra2/en/latest/chapters/chapter02.html) requires the infrastructure architecture to support dual stack for Kubernetes workloads. For workloads to be ready for that infrastructure, their Services should declare `PreferDualStack`. A Service without `ipFamilyPolicy` works on any single-family cluster (it gets a cluster IP from the configured range, IPv4 or IPv6), but on a dual-stack cluster it receives only the cluster's primary family. `PreferDualStack` closes that gap without affecting single-stack clusters — it falls back to one family where dual-stack is not enabled.

Sources: [Kubernetes dual-stack networking](https://kubernetes.io/docs/concepts/services-networking/dual-stack/); [Anuket Reference Architecture for Kubernetes (RA2) inf.ntw.04](https://cntt.readthedocs.io/projects/ra2/en/latest/chapters/chapter02.html).

#### Remediation

Set `spec.ipFamilyPolicy` to `PreferDualStack` on the CNF's Services so they are reachable over both address families on a dual-stack cluster. `PreferDualStack` works on single-stack clusters too — it falls back to one family without affecting behaviour.

#### Usage

`./cnti-testsuite dual_stack`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the Services of the CNF's installed manifest, Helm hooks left out. Each one is read from the cluster and its live `spec.ipFamilyPolicy` is judged. An `ExternalName` Service maps to a DNS name, has no cluster IP families and is not judged.
* **Verdicts**: a Service whose policy is `PreferDualStack` or `RequireDualStack` passes, and each one is listed with its policy in the test details. A Service whose policy is `SingleStack` (the value the API server records when the chart leaves the field out) or unset fails, with the reason. A Service in the manifest that is not found in the cluster is listed in the test details and not judged. A pass names how many Services were found and judged, and how many were not found, so it does not claim more than it checked.
* **Verdicts**: the test is skipped when no Service was judged and at least one was not found in the cluster, and not applicable when the CNF declares no Service, or only `ExternalName` ones.
* **Limits**: whether the CNF works over IPv6 needs a dual-stack cluster and is not tested.

</details>

----------

## Category: Microservice Tests

The CNF should be developed and delivered as a microservice. The CNTI Test Suite tests to determine the organizational structure and rate of change of the CNF being tested. Once these are known we can determine whether or not the CNF is a microservice. See: [Microservice-Principles](https://networking.cloud-native-principles.org/cloud-native-microservice-principles)

[Good microservice practices](https://vmblog.com/archive/2022/01/04/the-zeitgeist-of-cloud-native-microservices.aspx) promote agility which means less time will occur between deployments.  One benefit of more agility is it allows for different organizations and teams to deploy at the rate of change that they build out features, instead of deploying in lock step with other teams. This is very important when it comes to changes that are time sensitive like security patches.

### Usage

All microservice: `./cnti-testsuite microservice`

----------

### Reasonable Image Size

#### Overview

Checks the compressed size of every container image used by the CNF's workload resources. Each distinct image is pulled and measured once, and the measured size is reported per image.
Expectation: Each CNF image is under 5000 MB. A CNF may lower the limit with `image_size_max_mb` in the `common` section of `cnti-testsuite.yaml`. Images that cannot be pulled are reported and left out; the test is skipped when none could be measured.

#### Rationale

A CNF with smaller image sizes provides faster deployment and scaling (critical for functions like 5G control plane components), enables faster updates, reduces the risk of timeouts, and reduces the attack surface (key for regulated telecom environments).  In addition, smaller image sizes are important in edge/disaggregated deployments common in Open RAN and MEC scenarios.

Sources: [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

#### Remediation

Audit your CNF's images:

1. Identify and remove unused libraries, tools, and test artifacts.
2. Separate build-time from run-time dependencies.
3. Prefer distroless, alpine, or slim OS images.
4. Modularize large CNFs into separate containers or microservices.

#### Usage

`./cnti-testsuite reasonable_image_size`

----------

### Reasonable Startup Time

#### Overview

Measures, for each workload of the CNF, how long its slowest pod took from its containers starting to reporting Ready. A workload over the limit, 30 seconds unless the CNF configures another, fails the test, and so does a pod that never reports Ready.
Expectation: Every workload of the CNF is Ready within 30 seconds of its containers starting.

#### Rationale

Start-up time bounds how fast a CNF can scale out, recover from a pod loss and roll a new version; a pod that takes minutes to become Ready holds up every one of those. Long start-ups usually come from work done in the start-up path that belongs elsewhere, or from a fixed [readiness delay](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) standing in for a real readiness check; Kubernetes provides a startupProbe for the genuinely slow starters so that liveness settings need not be relaxed. Sources: [Kubernetes probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

Sources: [Kubernetes probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

#### Remediation

Move work out of the start-up path (lazy initialisation, pre-built caches, smaller images), gate readiness on what the service actually needs rather than on a fixed initial delay, and use a startupProbe for components that genuinely need longer. Set `startup_time_max_seconds` when the CNF's design justifies a longer limit.

#### Usage

`./cnti-testsuite reasonable_startup_time`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every workload of the CNF, through the pods it has when the test runs; no pod is restarted for the measurement. A pod's time runs from the latest start among its running containers to the moment the pod became Ready, both as recorded in the pod's status, so scheduling, image pulls and init containers are left out. A workload with no pod is named in the details and not judged. Jobs and CronJobs are not applicable, and the test is not applicable when the CNF has no other workload.
* **Configuration**: `startup_time_max_seconds` in the common section of `cnti-testsuite.yaml`: the limit, a positive number of seconds (30 by default).
* **Verdicts**: each workload is reported with its slowest pod and that pod's time. A workload whose slowest pod took longer than the limit is a finding, and so is each pod that has no running container or never became Ready, with its phase.
* **Limits**: the time is that of each pod's current start: a pod or container restarted by an earlier test, or by a crash, is measured from that restart. The reference is the last container to start, so in a pod whose containers start one after another the earlier containers' start-up is only partly counted.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Single Process Type in One Container

#### Overview

Checks that each container runs one application process type. Processes of one name count once, as an nginx parent and its workers do, but a container running both nginx and httpd fails. The container's PID 1 and the processes of a specialized init system are not counted.
Expectation: CNF container has one application process type.

#### Rationale

A microservice should have only one application process (or set of parent/child processes of the same type), optionally managed by an init/supervisor. The microservice should not spawn other process types (e.g., executables) as a way to contribute to the workload but rather should interact with other processes through a microservice API.

Sources: [CNTi CBPP-0005, single concern per container](https://github.com/lfn-cnti/bestpractices/blob/main/doc/cbpps/0005-single-concern-per-container.md); [Docker, running multiple services in a container](https://docs.docker.com/engine/containers/multi-service_container/); [The Twelve-Factor App, processes](https://12factor.net/processes).

#### Remediation

Ensure that there is only one process type within a container. This does not count against child processes, e.g., nginx or httpd could be a parent process with 10 child processes and pass this test, but if both nginx and httpd were running, this test would fail.

#### Usage

`./cnti-testsuite single_process_type`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every running, Ready container of the CNF's workloads, those of Jobs and CronJobs included; init containers are not inspected. The processes are read on the container's node: PID 1 and every process under it.
* **Verdicts**: a process type is a process name as the kernel reports it (the `Name` in `/proc/PID/status`, at most 15 characters). Not counted: PID 1, whatever it runs; a specialized init system (tini, tini-static, docker-init, dumb-init, catatonit, s6-svscan, gopherd) wherever it appears in the tree; and, when PID 1 is one, the init's own processes: s6-overlay runs as a family of `s6-*` processes (s6-supervise, s6-linux-init-shutdownd, s6-ipcserverd) under s6-svscan, and they are the init, not the workload. A container with more than one remaining type fails, and the details list its processes with their PIDs, parents and command lines; each container is otherwise reported with its one process type. Whether PID 1 is a recommended init system is judged by [Specialized Init Systems](#specialized-init-systems): a home-grown init does not fail this test, and when the container has application processes of another name it is named in the test output and the results file as not counted. Skipped when no container could be inspected.
* **Limits**: since PID 1 is never counted, a PID 1 whose children all share one other name passes, such as nginx as PID 1 with httpd children. A shell a process runs as a child (`sh -c`) is a process type of its own.
* **Common rules**: [Containers that cannot be inspected](#containers-that-cannot-be-inspected).

</details>

----------

### Service Discovery

#### Overview

Checks, for every workload resource of the CNF, that a Service of the CNF selects its pods; each workload is reported with the Service that exposes it, and each one nothing exposes is a finding. Application access for microservices within a cluster should be exposed via a Service. Read more about K8s Service [here](https://kubernetes.io/docs/concepts/services-networking/service/).
Expectation: Every workload resource of the CNF is exposed by a Service.

#### Rationale

A K8s microservice should expose its API through a K8s service resource. K8s services handle service discovery and load balancing for the cluster, ensuring that microservices can efficiently communicate and distribute traffic among themselves.

Sources: [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/); [The Twelve-Factor App, backing services](https://12factor.net/backing-services).

#### Remediation

Make sure the CNF exposes any of its containers as a Kubernetes Service. This is crucial for enabling service discovery and load balancing within the cluster, facilitating smoother operation and communication between microservices. You can learn more about Kubernetes Service [here](https://kubernetes.io/docs/concepts/services-networking/service/).

#### Usage

`./cnti-testsuite service_discovery`

----------

### Shared Database

#### Overview

Finds the databases among the CNF's workloads and watches, for up to a minute, which of the CNF's services connect to each one. A database that two or more services use fails the test. The test is not applicable when the CNF has no database.
Expectation: No database of the CNF is used by more than one service.

#### Rationale

A database shared by two services couples them: a schema change made for one breaks the other, they must upgrade in lock step and neither can be scaled, replaced or rolled back alone, which defeats the point of splitting them. This is the [integration database](https://martinfowler.com/bliki/IntegrationDatabase.html) anti-pattern; a service should own its data and expose it through its API. Sources: [Fowler, IntegrationDatabase](https://martinfowler.com/bliki/IntegrationDatabase.html); [microservices.io, database per service](https://microservices.io/patterns/data/database-per-service.html); [CBPP-0002 Microservices](https://github.com/lfn-cnti/bestpractices/blob/main/cbpps/cbpp-0002.md).

Sources: [The Twelve-Factor App, backing services](https://12factor.net/backing-services); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Give each service its own database (or its own schema with no cross-service access) and expose the data through the owning service's API instead of a shared database.

#### Usage

`./cnti-testsuite shared_database`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: a database is a container whose image's repository name, without registry, path, tag or digest, is `mariadb`, `mysql`, `percona` or `percona-server` (MariaDB/MySQL), `postgres` or `postgresql`, `mongo` or `mongodb`, `redis` or `valkey`, `cassandra` or `etcd`; failing that, one that declares the database's default port as a `containerPort` (3306, 5432, 27017, 6379, 9042, 2379). An exporter, operator or proxy whose image name only contains a database's name is not a database. Init containers are not looked at, and each database container is judged on its own. The clients are the pods of every other workload of the CNF, databases and Jobs included.
* **Verdicts**: a workload counts as a service when a Service of the CNF in its namespace selects its pods; a client no Service selects (a Job, a batch worker) is listed in the details as another client and does not count. A client is connected when one of its TCP connections, TIME_WAIT included, goes to a pod of the database on the database's default port, or to a cluster IP of a Service in the database's namespace that selects the database's pods, on one of that Service's ports. The connections are read on the client side, sampled every 5 seconds for up to 60 seconds per database; the watch ends early once every client workload has been seen. Every database is reported with the services and other clients that connected to it, or with none; a database with two or more services connected is a finding, and so is each of those services.
* **Limits**: only connections open during the watch, or closed less than about a minute before it, are seen: a service that does not talk to the database then is not counted. Clients outside the CNF, connections through a NodePort, an ingress or an external address, and connections to a database pod on a port other than its default one are not seen. A client pod whose process cannot be found on its node is named in the details and its connections are not read; a pod with no running container is left out.

</details>

----------

### Specialized Init Systems

#### Overview

Checks that each container's PID 1 is an init system made for containers: tini, dumb-init, catatonit, s6-overlay or gopherd. A container whose PID 1 is anything else, the application itself included, fails the test.
Expectation: Container images should use specialized init systems for containers.

#### Rationale

There are proper init systems and sophisticated supervisors that can be run inside of a container. Both of these systems properly reap and pass signals. Sophisticated supervisors are considered overkill because they take up too many resources and are sometimes too complicated. Some examples of sophisticated supervisors are: supervisord, monit, and runit. Proper init systems are smaller than sophisticated supervisors and therefore suitable for containers. Some of the proper container init systems are tini, dumb-init, catatonit, and s6-overlay.

Sources: [Docker, `--init` for signal handling and zombie reaping](https://docs.docker.com/reference/cli/docker/container/run/#init); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

#### Remediation

Use init systems that are purpose-built for containers like tini, dumb-init, catatonit, s6-overlay, gopherd.

#### Usage

`./cnti-testsuite specialized_init_system`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every container of the pods of the CNF's workloads; init containers are not inspected. Of a Job's or CronJob's pods only the running ones are inspected; a pod that has finished is listed in the test details. A pod with no container status yet lists each of its containers as not inspected.
* **Verdicts**: PID 1 passes when the command it was started as, the first word of its command line without its path, is `tini`, `tini-static`, `docker-init` (Docker's bundled tini), `dumb-init`, `catatonit`, `s6-svscan` (s6-overlay's PID 1) or `gopherd` (HAProxy's container init and supervisor); a path that merely contains one of these names does not count. A script started through its interpreter is judged by the interpreter's name. Each passing container is reported with its init, each failing one with the command PID 1 runs. A container whose PID 1 cannot be read, after three tries a few seconds apart, is listed as not inspected and does not fail the test. Skipped when a workload's pods cannot be listed, whatever else was found, and when no container's PID 1 could be read and some container could not be inspected.
* **Common rules**: [Containers that cannot be inspected](#containers-that-cannot-be-inspected), [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### System Init Not Used

#### Overview

Checks that no container's PID 1 is an init system made for a whole operating system: systemd, SysV init, upstart, BusyBox init, OpenRC or runit. A container that runs one fails the test; the application itself, or an init made for containers, passes.
Expectation: No container runs an operating-system init as its PID 1.

#### Rationale

An operating-system init boots a whole user space inside the container, which works against how Kubernetes runs it. It runs several services next to the application (journald, logind, udev, cron) that Kubernetes can neither observe nor restart or scale on their own, and it restarts a failing service itself, so the container's probes and restart count do not show the failure. Its services log to the journal rather than to stdout and stderr, out of reach of `kubectl logs` and log collectors. systemd needs a writable `/sys/fs/cgroup` and a tmpfs on `/run`, which usually means a privileged container. And it does not stop on SIGTERM, which Kubernetes sends unless the image declares another stop signal: systemd re-executes itself on SIGTERM and halts only on `SIGRTMIN+3`, so a container whose image does not declare that signal is killed at the end of its termination grace period, without a clean shutdown.

Sources: [systemd(1), Signals](https://www.freedesktop.org/software/systemd/man/latest/systemd.html#Signals); [CNTi CBPP-0005, single concern per container](https://github.com/lfn-cnti/bestpractices/blob/main/doc/cbpps/0005-single-concern-per-container.md); [Docker, running multiple services in a container](https://docs.docker.com/engine/containers/multi-service_container/).

#### Remediation

Run the application itself as PID 1, or under an init made for containers (tini, dumb-init, catatonit, s6-overlay, gopherd; see [Specialized Init Systems](#specialized-init-systems)). Move each service the operating-system init ran into its own container, send logs to stdout and stderr, and let Kubernetes probes and restart policies do what the init's service manager did.

#### Usage

`./cnti-testsuite system_init_not_used`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every container of the pods of the CNF's workloads; init containers are not inspected. Of a Job's or CronJob's pods only the running ones are inspected; a pod that has finished is listed in the test details. A pod with no container status yet lists each of its containers as not inspected.
* **Verdicts**: the check is on the executable PID 1 runs, read on the node from `/proc/PID/exe`, not on its command line: systemd is usually started as `/sbin/init`, a symlink to systemd itself, and a script named `init` runs as its interpreter. A container fails when that executable is named `systemd`, `init` (as SysV init, upstart and BusyBox's init symlinks are, and any other program of that name), `openrc-init`, `runit` or `runit-init`. BusyBox resolves to `busybox` whichever applet it runs, so it fails the test only when that applet is `init`: the name it was started under (`/proc/PID/comm`), as for Alpine's `/sbin/init` symlink, or its first argument when it was started as `busybox init`. Each passing container is reported with the executable its PID 1 runs, each failing one with that executable and the command it was started as.
* **Verdicts**: a container whose PID 1 cannot be read, after three tries a few seconds apart, is listed as not inspected and does not fail the test, and so is a BusyBox PID 1 whose name cannot be read. Skipped when a workload's pods cannot be listed, whatever else was found, and when no container's PID 1 could be read, including when the CNF's workloads have no pods.
* **Common rules**: [Containers that cannot be inspected](#containers-that-cannot-be-inspected), [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Sigterm Handled

#### Overview

Stops each container through the container runtime, as the kubelet does, and checks that it stops on its stop signal within the pod's termination grace period. When PID 1 supervises other processes, each of them must stop on the signal it is sent. A container the runtime has to kill fails.
Expectation: Sigterm is handled by PID 1 process of containers.

#### Rationale

The Linux kernel handles signals differently for the process that has PID 1 than it does for other processes. Signal handlers aren't automatically registered for this process, meaning that signals such as SIGTERM or SIGINT will have no effect by default. By default, one must kill processes by using SIGKILL, preventing any graceful shutdown. Depending on the application, using SIGKILL can result in user-facing errors, interrupted writes (for data stores), or unwanted alerts in a monitoring system.

Sources: [Kubernetes pod lifecycle, termination](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination); [The Twelve-Factor App, disposability](https://12factor.net/disposability).

#### Remediation

Make the PID 1 container process handle the container's stop signal (SIGTERM unless the image's `STOPSIGNAL` or the container's `lifecycle.stopSignal` says otherwise) and forward it to the processes it supervises; enable process namespace sharing in Kubernetes or use a specialized init system.

#### Usage

`./cnti-testsuite sig_term_handled`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every container of the CNF's workloads. A Job's process is its work, and ending it would change the Job's outcome: a Job or CronJob is listed in the test details as not applicable, and the test is not applicable when the CNF has no other workload.
* **Configuration**: the stop signal is the container's `lifecycle.stopSignal` when the cluster passes it to the runtime (Kubernetes' ContainerStopSignals feature), else the image's `STOPSIGNAL`, else SIGTERM. The runtime sends it to PID 1 and kills the container when the grace period is over: the pod's `terminationGracePeriodSeconds` (default 30 s), at most `CNTI_TESTSUITE_GENERIC_OPERATION_TIMEOUT` (default 60 s), so a longer grace period is judged at that limit.
* **Verdicts**: a container the runtime had to kill fails: its exit is waited for until the grace period is over, so a PID 1 that stops its children but not itself fails too. A process the tracer cannot attach to is judged by its outcome alone. A container is reported as skipped, and does not fail the test, when it could not be inspected (see the common rule), has no process to judge, cannot be stopped by the runtime, or when nothing failed but its exit could not be confirmed; one whose state cannot be read after the stop still fails when a process survived or was killed. A pod with no container status yet is left out. The details say which signal was sent, which signal stopped each process, and how long the container took to stop.
* **Verdicts**: when PID 1 supervises child processes, the children are judged: each must be stopped, with whatever shutdown signal the supervisor uses for it (SIGTERM, SIGINT, SIGQUIT, SIGHUP, SIGUSR1 or SIGUSR2), and terminate within the grace period; a child still running, one killed with SIGKILL rather than stopped, or one that crashes on the signal (SIGABRT, SIGSEGV), fails the container. A child with no handler for the signal it is sent ends on that signal's default action: it has stopped, and the details say so. When PID 1 is a specialized init system, the init's own processes are not judged, only the services it runs: s6-overlay, for example, ends its supervision tree (every `s6-*` process) itself once its services have stopped. A child that only keeps the container alive (`sleep`, `pause`, `tail -f /dev/null`, `cat` on stdin) is not the workload and is not judged; when it is the only child, PID 1 is judged itself, as a lone PID 1 is.
* **Common rules**: [Containers that cannot be inspected](#containers-that-cannot-be-inspected), [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Zombie Handled

#### Overview

Checks that each container's PID 1 reaps zombie processes. The test leaves an orphaned child process in every running, Ready application container for PID 1 to inherit, and a zombie still in the container after the child has exited fails the test.
Expectation: Zombie processes are handled/reaped by PID 1 process of containers.

#### Rationale

Classic init systems such as systemd are also used to remove (reap) orphaned, zombie processes. Orphaned processes — processes whose parents have died - are reattached to the process that has PID 1, which should reap them when they die. A normal init system does that. But in a container, this responsibility falls on whatever process has PID 1. If that process doesn't properly handle the reaping, you risk running out of memory or some other resources.

Sources: [Docker, `--init` for signal handling and zombie reaping](https://docs.docker.com/reference/cli/docker/container/run/#init); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

#### Remediation

Make the PID 1 container process to handle/reap zombie processes; enable process namespace sharing in Kubernetes or use specialized Init system.

#### Usage

`./cnti-testsuite zombie_handled`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every running, Ready regular container of the CNF's workloads, those of Jobs and CronJobs included; init and ephemeral containers are not probed. The probe runs from the cluster-tools pod on the container's node, inside the container's PID namespace, so nothing is written into the container: a read-only root filesystem or a distroless image is probed like any other. It starts a child that is orphaned at once onto the container's PID 1 and exits shortly after.
* **Configuration**: `CNTI_TESTSUITE_POD_READINESS_TIMEOUT` (180 s by default): the search for the CNF's running containers repeats for this long while none is running, as after the restarts Sigterm Handled causes. `CNTI_TESTSUITE_GENERIC_OPERATION_TIMEOUT` (60 s by default): after a zombie is found, the test restarts the pod and waits this long for it to restart, then this long again for it to be Ready, so up to twice this timeout.
* **Verdicts**: 10 seconds after the probes start, each container's processes are read again, and every process in the zombie state there, the probe's or any other, is a finding with its name, PID and parent. When every container was probed and passed, the details list the probed containers. Skipped, with every failed probe in the details, when the probe could not be started in some container, even if others were probed; and when no container could be probed.
* **Side effects**: a container in which a zombie was found is killed through the container runtime, and the test waits for its pod to restart and be Ready again; a pod that does not is not a finding.
* **Common rules**: [Containers that cannot be inspected](#containers-that-cannot-be-inspected).

</details>

----------

## Category: State Tests

The CNTI Test Suite checks if state is stored in a [custom resource definition](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) or a separate database (e.g. [etcd](https://github.com/etcd-io/etcd)) rather than requiring local storage. It also checks to see if state is resilient to node failure

If infrastructure is immutable, it is easily reproduced, consistent, disposable, will have a repeatable deployment process, and will not have configuration or artifacts that are modifiable in place.
This ensures that all *configuration* is stateless.
Any [*data* that is persistent](https://vmblog.com/archive/2022/05/16/stateful-cnfs.aspx) should be managed by K8s statefulsets.

### Usage

All state: `./cnti-testsuite state`

----------

### Node drain

#### Overview

Every schedulable node that hosts a pod of the CNF's Deployments, StatefulSets or ReplicaSets is cordoned and drained once, one node at a time, and every Deployment, StatefulSet or ReplicaSet with a pod there must be Ready again on another node while the drained node is still cordoned.
Expectation: All workload resources are successfully rescheduled onto other available node(s).

#### Rationale

No CNF should fail because of stateful configuration. A CNF should function properly if it is rescheduled on other nodes.
This test will remove resources which are running on a target node and reschedule them on another node.

Sources: [Safely drain a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/); [Kubernetes disruptions and PodDisruptionBudgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/).

#### Remediation

Ensure that your CNF can be successfully rescheduled when a node fails or is [drained](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/). When the cluster's default storage class ties volumes to one node, run the test on a cluster whose default storage follows a pod to another node, or have the CNF name an elastic storage class for its claims.

#### Usage

`./cnti-testsuite node_drain`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the Deployments, StatefulSets and ReplicaSets that have a pod on a node when its drain starts. The pods on a node are read just before it is drained, so pods an earlier drain moved there are judged with it. A node hosting only bare Pods, DaemonSet, Job or CronJob pods is not drained. Which nodes are schedulable is read once, when the test starts: a hosting node that was not schedulable then is named in the details and not drained, and a node cordoned while the test runs is still drained. Bare Pods, DaemonSets, Jobs and CronJobs are reported as not applicable: a drain deletes a bare Pod for good, leaves a DaemonSet's pods in place, and a Job's pod runs to completion. Skipped when the cluster has fewer than two schedulable nodes.
* **Configuration**: `CNTI_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION`: how long a node stays cordoned, in seconds (30 by default), counted from the start of its drain, so a drain and recovery that take longer than this uncordon the node as soon as they end. A node whose drain does not complete is uncordoned at once, without the hold.
* **Verdicts**: a workload is Ready again when it has as many pods as it asks for, all Ready and none on the drained node. A workload that does not come back, whose eviction the API refuses (a PodDisruptionBudget, usually), or that has no scheduled pod to drain when the test starts, is a finding with the reason. The details record, per node, how many pods were evicted and how long it took, and per workload how long it took to be Ready again.
* **Verdicts**: a workload that cannot be rescheduled because its volume is tied to the drained node by the cluster's default storage class (the scheduler reports a volume node affinity conflict, and `elastic_volumes` would call the volume the cluster's choice) is listed with the reason and not judged: the CNF took the storage the cluster offers, and the same chart passes where the default storage follows a pod; it comes back when the node does, and the test is not applicable when every workload is in that state. Storage tied to a node that the CNF chose itself (a `local` or `hostPath` PersistentVolume, a node-local storage class it names) stays a finding.
* **Side effects**: each node is drained with `kubectl drain`, DaemonSet pods ignored and emptyDir data deleted; no chaos tool is involved. Before it ends, the test waits for every workload it has not already failed to be Ready again, so the tests after it start from a settled CNF; a workload that is still not Ready then fails too.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### No local volume configuration

#### Overview

Checks that no persistent volume claim of the CNF's workloads is bound to a local PersistentVolume, which ties the workload to one node and its disk. A local volume fails the test. A claim bound to no volume leaves its storage undetermined, and the test is then skipped rather than passed.
Expectation: Local storage should not be used or configured.

#### Rationale

A [local volume](https://kubernetes.io/docs/concepts/storage/volumes/#local) is a disk or a directory of one node. A pod that uses it can only run on that node: Kubernetes schedules it there through the volume's node affinity and cannot move it elsewhere.
When the node fails or is drained, the workload stays down until the node is back, and when the node or its disk is lost, the data is lost with it. Kubernetes does not replicate or move a local volume; an application that uses one has to tolerate that itself.
A CNF that keeps its state on storage that is reachable from any node, a network or cloud volume claimed through a StorageClass, can be rescheduled with its data.

Sources: [Kubernetes local volumes](https://kubernetes.io/docs/concepts/storage/volumes/#local); [Kubernetes persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Back each persistent volume claim with a network or cloud volume, claimed through a StorageClass, instead of a PersistentVolume of type `local`.

#### Usage

`./cnti-testsuite no_local_volume_configuration`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the claims the pod volumes of the CNF's workloads name (`persistentVolumeClaim.claimName`), as the installed manifests declare them, Jobs and CronJobs included. The claims a StatefulSet makes from its volumeClaimTemplates are not checked. A CNF with no such claim passes.
* **Verdicts**: a claim's PersistentVolume is local when it sets `spec.local.path`; the storage class name is not judged, since a class named `local-storage` can be backed by anything. Each local volume is a finding with the workload, the volume, the claim, the PersistentVolume and its path. A claim no PersistentVolume is bound to is listed in the details as undetermined, and the test is skipped when nothing local was found but some claim was unbound. A resource or volume that cannot be read is a test error, not a pass.
* **Limits**: a hostPath PersistentVolume, or one whose node affinity names a host, is not a local volume here; [Elastic volumes](#elastic-volumes) judges those. A PersistentVolume is matched by its claim's name alone, so a volume bound to a claim of the same name in another namespace is judged too.

</details>

----------

### Elastic volumes

#### Overview

Checks that the CNF's persistent volumes are elastic: not tied to one node, so that a workload can be rescheduled with its data. A local or hostPath volume, or one pinned to a node, fails the test, unless the cluster's default storage class provisioned it.
Expectation: Persistent volumes should be able to follow the workload to another node.

#### Rationale

A cnf that uses elastic volumes can be rescheduled to other nodes by the orchestrator easily

Sources: [Kubernetes persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Claim the storage from a storage class whose volumes can follow the workload to another node, and do not bind the claim to a local or hostPath PersistentVolume.

#### Usage

`./cnti-testsuite elastic_volumes`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the PersistentVolume each claim of the CNF's workloads is bound to, Jobs and CronJobs included: the claims its pod volumes name and, for a StatefulSet, those made from its volumeClaimTemplates, one per template and replica of its current replica count. A volume belongs to a claim when its claim reference names the claim and its namespace.
* **Verdicts**: a volume is tied to a node when it is a `local` or `hostPath` volume, or when its node affinity names a host (`kubernetes.io/hostname`, or the node's `metadata.name`). A node affinity on a zone or a region, as cloud disks carry, does not tie it, and the name of the provisioner is not judged. A tied volume is a finding unless a provisioner made it and its storage class is the one the cluster marks as default: it is then the cluster's choice, listed in the test details and not judged. A tied volume created by hand, or of a class that is not the default, stays a finding.
* **Verdicts**: the test fails when any volume is a finding, and otherwise passes when at least one volume is elastic, even if other claims are unbound or the cluster's choice. It is not applicable when no persistent volumes are used, or when every bound volume is the cluster's choice, and skipped when no claim is bound to a volume. An unbound claim is listed in the details.

</details>

----------

### Database persistence

#### Overview

Checks that each database of the CNF keeps its data on persistent storage: its workload must claim a persistent volume, and a database without one fails the test. A Redis or Valkey without one may be a cache and is not judged. The test is not applicable when the CNF has no database.
Expectation: Databases should keep their data on persistent volumes, so that it survives the rescheduling of their pods.

#### Rationale

When a traditional database such as mysql is configured to use statefulsets, it allows the database to use a persistent identifier that it maintains across any rescheduling.
Persistent Pod identifiers make it easier to match existing volumes to the new Pods that have been rescheduled.
<https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/>

Sources: [Kubernetes persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/); [The Twelve-Factor App, backing services](https://12factor.net/backing-services).

#### Remediation

Give the database a persistent volume: a volumeClaimTemplate in a StatefulSet, or a PersistentVolumeClaim.

#### Usage

`./cnti-testsuite database_persistence`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the databases are found as in [Shared Database](#shared-database): MariaDB/MySQL, PostgreSQL, MongoDB, Redis, Cassandra and etcd, by the image's repository name or by the database's default port. Every kind of workload counts, Jobs and CronJobs included, and a workload is judged once, by its first database container.
* **Verdicts**: a database passes when its workload claims persistent storage, through a PersistentVolumeClaim its pod volumes name or a StatefulSet's volumeClaimTemplate, whatever the kind of the workload; the claim does not have to be bound. It fails without one: an emptyDir or a hostPath volume is not persistent storage here. The provisioner behind the claim is the cluster's choice and is not judged here; see [Elastic volumes](#elastic-volumes). A Redis, or its fork Valkey, without a persistent volume may be a cache: it is listed in the test details and not judged. The test is not applicable when no database is found, or when every database found is such a Redis.

</details>

----------

## Category: Reliability, Resilience and Availability Tests

[Cloud Native Definition](https://github.com/cncf/toc/blob/master/DEFINITION.md) requires systems to be Resilient to failures inevitable in cloud environments. CNF Resilience should be tested to ensure CNFs are designed to deal with non-carrier-grade shared cloud HW/SW platform

Cloud native systems promote resilience by putting a high priority on testing individual components (chaos testing) as they are running (possibly in production).
[Reliability in traditional telecommunications](https://vmblog.com/archive/2021/09/15/cloud-native-chaos-and-telcos-enforcing-reliability-and-availability-for-telcos.aspx) is handled differently than in Cloud Native systems. Cloud native systems try to address reliability (MTBF) by having the subcomponents have higher availability through higher serviceability (MTTR) and redundancy. For example, having ten redundant subcomponents where seven components are available and three have failed will produce a top level component that is more reliable (MTBF) than a single component that "never fails" in the cloud native world.

The chaos tests run LitmusChaos experiments, one per workload. When Litmus skips an experiment (its runner found no ChaosExperiment to run, or could not create the experiment job), nothing was injected and the CNF was not tested: the test ends as an error, not a failure, and its details carry Litmus's own reason: the events on the engine (`ExperimentSkipped`, `ExperimentNotFound`, `JobCreationError`, ...), the runner pod's last log lines and whether the ChaosExperiment exists in the namespace. The test does not wait for a verdict that cannot come. The same holds when the fault cannot be installed (its template could not be fetched after the network retries, or the cluster refused the experiment or its RBAC): the test ends as an error naming the fault, the step and the reason.

### Usage

All resilience: `./cnti-testsuite resilience`

----------

### CNF under network latency

#### Overview

Delays the network traffic of each of the CNF's workloads with the LitmusChaos [pod-network-latency](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-latency/) fault, one workload at a time, and takes Litmus's verdict on each run.
Expectation: The CNF should continue to function when network latency occurs.

#### Rationale

Network latency can have a significant impact on the overall performance of the application.  Network outages that result from low latency can cause
a range of failures for applications and can severely impact user/customers with downtime. This chaos experiment allows you to see the impact of latency
traffic on the CNF.

Sources: [LitmusChaos pod-network-latency fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-latency/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF doesn't stall or get into a corrupted state when network degradation occurs.
A mitigation strategy (in this case keep the timeout i.e., access latency low) could be via some middleware that can switch traffic based on some SLOs parameters.

#### Usage

`./cnti-testsuite pod_network_latency`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault adds 60 s of latency (`NETWORK_LATENCY` 60000 ms) to the egress traffic on `eth0` of the target container for 60 s.
* **Verdicts**: Litmus's verdict, as described in [Chaos tests](#chaos-tests): this fault does not check the CNF's pods, so a pass means the latency was injected and the experiment completed.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### CNF with host disk fill

#### Overview

Fills the ephemeral storage of each of the CNF's workloads with the LitmusChaos [disk-fill](https://litmuschaos.github.io/litmus/experiments/categories/pods/disk-fill/) fault, one workload at a time, and takes Litmus's verdict. A workload whose containers are all read-only passes without the fault.
Expectation: The CNF should continue to function when disk fill occurs and pods should not be evicted to another node.

#### Rationale

Disk Pressure is a scenario we find in Kubernetes applications that can result in the eviction of the application replica and impact its delivery. Such scenarios can still occur despite whatever availability aids K8s provides. These problems are generally referred to as "Noisy Neighbour" problems.

Sources: [LitmusChaos disk-fill fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/disk-fill/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient and doesn't stall when heavy IO causes a degradation in storage resource availability.

#### Usage

`./cnti-testsuite disk_fill`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault writes into a writable container of the workload, the first whose root file system is not read-only, until 80 % of that container's ephemeral-storage limit is used (Litmus's `FILL_PERCENTAGE`), and holds it for 60 s. A container without an ephemeral-storage limit gets nothing written: Litmus then fills `EPHEMERAL_STORAGE_MEBIBYTES`, which is not set.
* **Configuration**: the fault fills the target container's directory under the container runtime's root on the node, which the suite finds for the detected runtime (containerd, CRI-O, docker; k3s, RKE2 and microk8s paths included) and names in the details; `CNTI_TESTSUITE_CONTAINER_PATH` overrides it. The test is not applicable when the runtime is unsupported or the directory is not found.
* **Verdicts**: a workload whose containers all mount a read-only root file system cannot be filled at all, which is the property this fault probes, so it passes without the fault and the reason is in the details; when every workload is like that, the test passes saying so. A writable container without an ephemeral-storage limit gets nothing written, and Litmus still gives the run `Pass` (see Scope). Otherwise Litmus's verdict, as described in [Chaos tests](#chaos-tests): this fault does not check the CNF's pods.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### Pod delete

#### Overview

Deletes pods of each of the CNF's workloads with the LitmusChaos [pod-delete](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-delete/) fault, one workload at a time, and passes when Litmus sees the deleted pods recreated and running.
Expectation: The CNF should continue to function when pod delete occurs.

#### Rationale

In a distributed system like Kubernetes, application replicas may not be sufficient to manage the traffic (indicated by SLIs) when some replicas are unavailable due to any failure (can be system or application). The application needs to meet the SLO (service level objectives) for this. It's imperative that the application has defenses against this sort of failure to ensure that the application always has a minimum number of available replicas.

Sources: [LitmusChaos pod-delete fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-delete/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient and doesn't fail on a forced/graceful pod failure on specific or random replicas of an application.

#### Usage

`./cnti-testsuite pod_delete`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault deletes a pod of the workload gracefully (`FORCE` false) every 10 s for 30 s. It needs no container runtime socket.
* **Verdicts**: Litmus's verdict, as described in [Chaos tests](#chaos-tests). This is the one fault that checks the CNF: after each deletion Litmus waits for the workload's pods to be recreated and running, and the run fails when they are not.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### Memory hog

#### Overview

Starts a memory stress process in each of the CNF's workloads with the LitmusChaos [pod-memory-hog](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-memory-hog/) fault, one workload at a time, and takes Litmus's verdict on each run.
Expectation: The CNF should continue to function when pod memory hog occurs.

#### Rationale

Memory is the one resource Kubernetes cannot throttle: a container that needs more than it may have is killed, not slowed down. The test promotes the Kubernetes practices that decide what happens then, and it holds for any Kubernetes workload, not only network functions.

* **A memory request and limit on every container.** The request is what the scheduler reserves on the node; the limit is the ceiling the kernel enforces on the container's cgroup. A container that exceeds its limit is OOM-killed on its own, and the pod is restarted by its controller. A container without a limit competes with everything else on the node.
* **The QoS class the pod gets from them.** Requests equal to limits make the pod `Guaranteed`; requests below limits make it `Burstable`; neither makes it `BestEffort`. When a node runs short of memory, the kubelet evicts `BestEffort` pods first, then `Burstable` pods using more than they requested, and `Guaranteed` pods last; the kernel's OOM killer ranks processes the same way through the `oom_score_adj` the kubelet assigns per class.
* **Surviving the loss of a container.** A pod that is killed and restarted must come back on its own: a liveness probe, a readiness probe that holds traffic until it can serve, and replicas spread so one restart is not an outage.

The experiment consumes most of the memory available to the target container for the duration of the fault. With limits set, the pressure stays inside that container and the test shows whether the workload recovers from an OOM kill; without them, the pressure reaches the node and the eviction order above decides which pods, of this CNF or another, are lost.

Sources: [Kubernetes: Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/); [Kubernetes: Pod Quality of Service Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/); [Kubernetes: Node-pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/); [LitmusChaos pod-memory-hog fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-memory-hog/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Set a memory request and limit on every container, sized from what the workload uses under load, so that pressure stays inside the container and the pod keeps a predictable QoS class. Give the workload liveness and readiness probes and more than one replica where it serves traffic, so a container the kernel kills is replaced without an outage. Then run the test again: it passes when the workload keeps serving through the fault and recovers after it.

#### Usage

`./cnti-testsuite pod_memory_hog`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault runs a process that takes 80 MB (`MEMORY_CONSUMPTION`) in the target container for 60 s. Where the container has a memory limit, the stress counts against it and can constrain the container's own process; without one, it takes memory from the node.
* **Verdicts**: Litmus's verdict, as described in [Chaos tests](#chaos-tests): this fault does not check the CNF's pods, so a pass means the stress ran and the experiment completed.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### IO Stress

#### Overview

Stresses the file system of each of the CNF's workloads with continuous writes, using the LitmusChaos [pod-io-stress](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-io-stress/) fault, one workload at a time, and takes Litmus's verdict. A workload whose containers are all read-only passes without the fault.
Expectation: The CNF should continue to function when pod io stress occurs.

#### Rationale

Stressing the disk with continuous and heavy IO can cause degradation in reads/writes by other microservices that use this
shared disk.  Scratch space can be used up on a node which leads to the lack of space for newer containers to get scheduled which
causes a movement of all pods to other nodes. This test determines the limits of how a CNF uses its storage device.

Sources: [LitmusChaos pod-io-stress fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-io-stress/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to continuous and heavy disk IO load and can maintain some level of availability

#### Usage

`./cnti-testsuite pod_io_stress`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault writes to the root file system of a writable container of the workload, the first whose root file system is not read-only, up to 50 % of its free space (`FILESYSTEM_UTILIZATION_PERCENTAGE`), for 120 s.
* **Verdicts**: a workload whose containers all mount a read-only root file system cannot be stressed at all, which is the property this fault probes, so it passes without the fault and the reason is in the details; when every workload is like that, the test passes saying so. Otherwise Litmus's verdict, as described in [Chaos tests](#chaos-tests): this fault does not check the CNF's pods.
* **Verdicts**: on a memory-backed root file system (a `tmpfs`, such as containerd's root on a kind node's `/tmp`) there is no disk I/O to stress: the file is charged to the container's memory limit as `shmem`, so a write would stress memory and a pass would say nothing about I/O. Such a workload is not injected and the reason is in the details; the test is not applicable when no workload could be injected for that reason. When the file system type cannot be probed, the fault is injected and the failed probe is in the details.
* **Side effects**: afterwards the suite deletes the resources of Kubernetes' `all` category (pods, services, deployments, replica sets, jobs and the like) labeled `app.kubernetes.io/part-of=litmus` in the `default` namespace. Service accounts, RBAC and Litmus's custom resources are not in that category and stay.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### Network corruption

#### Overview

Corrupts the network packets of each of the CNF's workloads with the LitmusChaos [pod-network-corruption](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-corruption/) fault, one workload at a time, and takes Litmus's verdict on each run.
Expectation: The CNF should be resilient to a lossy/flaky network and should continue to provide some level of availability.

#### Rationale

A higher quality CNF should be resilient to a lossy/flaky network.  This test injects packet corruption on the specified CNF's container by
starting a traffic control (tc) process with netem rules to add egress packet corruption.

Sources: [LitmusChaos pod-network-corruption fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-corruption/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to a lossy/flaky network and can maintain a level of availability.

#### Usage

`./cnti-testsuite pod_network_corruption`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault corrupts every egress packet (`NETWORK_PACKET_CORRUPTION_PERCENTAGE` 100) on `eth0` of the target container for 60 s, with a traffic control (`tc`) netem rule.
* **Verdicts**: Litmus's verdict, as described in [Chaos tests](#chaos-tests): this fault does not check the CNF's pods, so a pass means the corruption was injected and the experiment completed.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### Network duplication

#### Overview

Duplicates the network packets of each of the CNF's workloads with the LitmusChaos [pod-network-duplication](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-duplication/) fault, one workload at a time, and takes Litmus's verdict on each run.
Expectation: The CNF should continue to function and be resilient to a duplicate network.

#### Rationale

A higher quality CNF should be resilient to erroneously duplicated packets. This test injects network duplication on the specified container
by starting a traffic control (tc) process with netem rules to add egress delays.

Sources: [LitmusChaos pod-network-duplication fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-duplication/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to erroneously duplicated packets and can maintain a level of availability.

#### Usage

`./cnti-testsuite pod_network_duplication`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault duplicates every egress packet (`NETWORK_PACKET_DUPLICATION_PERCENTAGE` 100) of the target container for 60 s, with a traffic control (`tc`) netem rule.
* **Verdicts**: Litmus's verdict, as described in [Chaos tests](#chaos-tests): this fault does not check the CNF's pods, so a pass means the duplication was injected and the experiment completed.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### Pod DNS errors

#### Overview

Makes DNS resolution fail in each of the CNF's workloads with the LitmusChaos [pod-dns-error](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-dns-error/) fault, one workload at a time, and takes Litmus's verdict on each run.
Expectation: The CNF does not crash and is resilient to DNS resolution failures.

#### Rationale

A CNF should be resilient to name resolution (DNS) disruptions within the kubernetes pod. This ensures that at least some application availability will be maintained if DNS resolution fails.

Sources: [LitmusChaos pod-dns-error fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-dns-error/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to DNS resolution failures and can maintain a level of availability.

#### Usage

`./cnti-testsuite pod_dns_error`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the fault makes the resolution of every host name fail (`TARGET_HOSTNAMES` empty) in the target container for 120 s.
* **Verdicts**: Litmus's verdict, as described in [Chaos tests](#chaos-tests): this fault does not check the CNF's pods, so a pass means the DNS errors were injected and the experiment completed.
* **Common rules**: [Chaos tests](#chaos-tests).

</details>

----------

### Liveness probe

#### Overview

This test verifies that each workload resource includes at least one container with a liveness probe configured.
Expectation: Each workload resource should have at least one container with a liveness probe defined.

#### Rationale

A cloud native principle is that application developers understand their own resilience requirements better than operators:

> "No one knows more about what an application needs to run in a healthy state than the developer. For a long time, infrastructure administrators have tried to figure out what “healthy” means for applications they are responsible for running. Without knowledge of what actually makes an application healthy, their attempts to monitor and alert when applications are unhealthy are often fragile and incomplete. To increase the operability of cloud native applications, applications should expose a health check." -- Garrison, Justin; Nova, Kris. Cloud Native Infrastructure: Patterns for Scalable Infrastructure and Applications in a Dynamic Environment. O'Reilly Media. Kindle Edition.

This is exemplified in the Kubernetes best practice of pods declaring how they should be managed through the liveness and readiness entries in the pod's configuration.

Sources: [Kubernetes probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF has a [Liveness Probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) configured.

#### Usage

`./cnti-testsuite liveness`

----------

### Readiness probe

#### Overview

This test verifies that each workload resource includes at least one container with a readiness probe configured.
Expectation: Each workload resource should have at least one container with a readiness probe defined.

#### Rationale

A CNF should tell Kubernetes when it is [ready to serve traffic](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-readiness-probes).

Sources: [Kubernetes probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF has a [Readiness Probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) configured.

#### Usage

`./cnti-testsuite readiness`

----------

### Startup probe

#### Overview

Checks the CNF manifest for containers with a positive liveness probe initial delay and no startup probe. A container without a liveness probe is outside the check. The test is not applicable when no container declares a liveness probe.

#### Rationale

A startup probe gives a slow-starting container time to initialize. Kubernetes waits for it to succeed before running the liveness probe.

Sources: [Kubernetes probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/).

#### Remediation

Add a startup probe and size its failure threshold and period for the container's startup time.

#### Usage

`./cnti-testsuite startup_probe`

----------

### Pod owner

#### Overview

Checks that every pod of the CNF is owned by a controller, such as a Deployment, StatefulSet, DaemonSet, Job or an operator's custom resource, that recreates it when its node fails or is drained. A bare Pod, created directly with no controller owning it, fails the test.
Expectation: Every pod of the CNF is owned by a controller.

#### Rationale

A Pod created directly, without a Deployment, StatefulSet, DaemonSet or Job owning it, is not recreated when its node fails or is drained, and it cannot be scaled or rolled out.

Sources: [Kubernetes: Working with Pods](https://kubernetes.io/docs/concepts/workloads/pods/#working-with-pods); [Red Hat certsuite: lifecycle-pod-owner-type](https://github.com/redhat-best-practices-for-k8s/certsuite/blob/main/CATALOG.md#lifecycle-pod-owner-type).

#### Remediation

Run the pods through a Deployment, StatefulSet, DaemonSet or Job instead of creating bare Pods.

#### Usage

`./cnti-testsuite pod_owner`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the live pods of each of the CNF's workloads, and each Pod the manifest declares. A pod with no controller that carries a workload's selector labels is counted as that workload's pod. Pods already being deleted and pods with a `helm.sh/hook` annotation (such as a chart's `*-test-connection` Pod) are left out: hooks are not part of the CNF's workloads, in the manifest as in the cluster.
* **Verdicts**: a pod passes when it has an owner reference with `controller: true`, whatever its kind, so a pod whose controller is an operator's custom resource counts as owned. A pod without one is a finding; for a Pod the manifest declares, the reason says it is declared as a bare Pod. Each pod is reported once, however many workloads select it. The pass and failure messages give the number of pods judged. The test is skipped when the CNF has no pod to read (for example, a workload scaled to zero), and not applicable when the CNF has no workload.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

## Category: Observability and Diagnostic Tests

In order to maintain, debug, and have insight into a production environment that is protected (versioned, kept in source control, and changed only by using a deployment pipeline), its infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends themselves to metrics, tracing, and logging.

### Usage

All observability: `./cnti-testsuite observability`

----------

### Use stdout/stderr for logs

#### Overview

Checks that the CNF writes logs to stdout/stderr, where Kubernetes collects them. A workload passes when at least one of its pods has log output, and fails when every pod of it that could be read printed nothing. Pods whose logs cannot be read yet are reported and not judged.
Expectation: Resource output logs should be sent to STDOUT/STDERR

#### Rationale

By sending logs to standard out/standard error [logs will be treated like event streams](https://12factor.net/) as recommended by 12 factor apps principles.

Sources: [The Twelve-Factor App, logs](https://12factor.net/logs); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Make sure applications and CNF's are sending log output to STDOUT and or STDERR.

#### Usage

`./cnti-testsuite log_output`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every pod of each of the CNF's workloads (Deployments, StatefulSets, DaemonSets, ReplicaSets, bare Pods, Jobs and CronJobs; Helm hooks left out). A pod is read when it is Running, or Succeeded: a pod that ran to completion (a Job's) keeps its logs and is read like a running one. A pod in any other phase (Pending, not scheduled, Failed, Unknown), or whose logs `kubectl` cannot return (a container still starting), is listed in the test details with the reason and left out of the verdict. A Job or CronJob that ran and was removed is not judged.
* **Verdicts**: the last five log lines of all the pod's containers are read. A workload passes when any of its pods has written anything; when every readable pod of it is silent, each of them is a finding. A workload with no readable pod is not judged. The details name, per passing workload, the pods that logged. The test is skipped when no pod's logs could be read, and not applicable when the CNF has no workload.
* **Limits**: only the current instance of each container is read, not the log of one that restarted. The test checks that output exists, not its content, and not that the CNF writes no logs to files as well.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Prometheus installed

#### Overview

Checks that a Prometheus server in the cluster has every workload of the CNF among its scrape targets. The test finds the server, reads its active targets, and fails for each workload none of whose pods is a target; whether a target is up is not judged. When no Prometheus server in the cluster answers, the test is not applicable.
Expectation: The CNF is configured and sending metrics to a Prometheus server.

#### Rationale

Recording metrics within a cloud native deployment is important because it gives the maintainer of a cluster of hundreds or thousands of services the ability to pinpoint [small anomalies](https://about.gitlab.com/blog/2018/09/27/why-all-organizations-need-prometheus/), such as those that will eventually cause a failure.

Sources: [OpenMetrics specification](https://github.com/prometheus/OpenMetrics/blob/main/specification/OpenMetrics.md); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Install and configure Prometheus for your CNF.

#### Usage

`./cnti-testsuite prometheus_traffic`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every workload of the CNF but its Jobs and CronJobs, which serve nothing to scrape: they are listed in the test details as not applicable, and the test is not applicable when the CNF has no other workload. The Prometheus server need not be the CNF's: any one in the cluster counts.
* **Verdicts**: the server is found on the schedulable nodes as a ready container whose command line contains `prometheus`, with a Service in any namespace selecting its pod. Each TCP port of that Service is probed at `http://SERVICE.NAMESPACE.svc.cluster.local:PORT/api/v1/targets?state=active` (`https` on port 443), 10 seconds each, and the first one that answers is the server. Not applicable, with the pods and URLs probed in the details, when no Prometheus process is found or none answers: nothing scrapes the CNF in that cluster.
* **Verdicts**: a workload is scraped when an active target's URL is on one of its pods' IPs, on any port. The details name the server, the URL its targets API answered at and, per workload, the scrape URL and target health. A workload no target scrapes is a finding, with its pod IPs or the note that its pods have no IP yet; the test fails when any workload is not scraped. A target's health is reported, not judged: a target that is down still counts as scraping the workload.
* **Limits**: the match is by IP address, so a pod on the host network shares its node's IP and is matched by any target on that node. Only the targets active when the test runs are read. A Prometheus container that is not ready, or runs on a node that is not schedulable, is not found.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Routed logs

#### Overview

Checks for presence of a Unified Logging Layer and if the CNFs logs are being captured by the Unified Logging Layer. fluentd and fluentbit are currently supported. Of a Job's or CronJob's pods only the running ones are judged; a pod that has finished is listed in the test details.
Expectation: Fluentd or FluentBit is installed and capturing logs for the CNF.

#### Rationale

A CNF should have logs managed by a [unified logging layer](https://www.fluentd.org/why) It's considered a best-practice for CNFs to route logs and data through programs like fluentd to analyze and better understand data.

Sources: [The Twelve-Factor App, logs](https://12factor.net/logs).

#### Remediation

Install and configure fluentd or fluentbit to collect data and logs. See more at [fluentd.org](https://bit.ly/fluentd) for fluentd or [fluentbit.io](https://fluentbit.io/) for fluentbit.

#### Usage

`./cnti-testsuite routed_logs`

----------

### OpenMetrics compatible

#### Overview

Fetches every endpoint Prometheus scrapes on the CNF's pods and runs it through the [OpenMetrics](https://openmetrics.io/) validator; each endpoint is reported by URL with the validator's verdict, and a failing one is a finding with the validator's message. Not applicable when no Prometheus server answers; skipped when a server answers but no endpoint of the CNF is scraped.
Expectation: CNF should emit OpenMetrics compatible traffic.

#### Rationale

OpenMetrics is the de facto standard for transmitting cloud native metrics at scale, with support for both text representation and Protocol Buffers and brings it into an Internet Engineering Task Force (IETF) standard. A CNF should expose metrics that are [OpenMetrics compatible](https://github.com/OpenObservability/OpenMetrics/blob/main/specification/OpenMetrics.md)

Sources: [OpenMetrics specification](https://github.com/prometheus/OpenMetrics/blob/main/specification/OpenMetrics.md).

#### Remediation

Ensure that your CNF is publishing OpenMetrics compatible metrics.

#### Usage

`./cnti-testsuite open_metrics`

----------

### Jaeger tracing

#### Overview

Checks whether the CNF's pods actually emit traces: the test queries the Jaeger API for recent traces and matches their process tags against the CNF's pods. Not applicable when no Jaeger is installed on the cluster: nothing collects the CNF's traces there.
Expectation: The CNF is sending traces to Jaeger.

#### Rationale

A CNF should provide tracing that conforms to the [open telemetry tracing specification](https://opentelemetry.io/docs/reference/specification/trace/api/)

Sources: [OpenTelemetry](https://opentelemetry.io/docs/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Instrument your CNF with OpenTelemetry or Jaeger client libraries and point it at the cluster's tracing agent or collector, so its spans arrive in Jaeger.

#### Usage

`./cnti-testsuite tracing`

----------

### Termination message policy

#### Overview

Checks that each container of the CNF, init containers included, sets `terminationMessagePolicy: FallbackToLogsOnError`. Ephemeral containers are added by `kubectl debug`, not by the CNF, and are not judged.
Measurement: the policy is read from the live workload resources. The API server defaults an unset field to `File`, so an unset policy and an explicit `File` are the same finding.
Expectation: Every container of the CNF sets `terminationMessagePolicy: FallbackToLogsOnError`.

#### Rationale

When a container fails, Kubernetes shows the reason in the pod status only if the container writes `/dev/termination-log`, which few do. With `FallbackToLogsOnError`, Kubernetes uses the end of the container's log instead when the container exits with an error, so the reason is visible in `kubectl describe pod` without reading the logs of a container that may already be gone.

Sources: [Kubernetes: Determine the Reason for Pod Failure](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/#customizing-the-termination-message); [Red Hat certsuite: observability-termination-policy](https://github.com/redhat-best-practices-for-k8s/certsuite/blob/main/CATALOG.md#observability-termination-policy).

#### Remediation

Set `terminationMessagePolicy: FallbackToLogsOnError` on each container and init container.

#### Usage

`./cnti-testsuite termination_message_policy`

----------

## Category: Security Tests

CNF containers should be isolated from one another and the host. The CNTI Test Suite uses tools like [Armosec Kubescape](https://github.com/armosec/kubescape)

> "Cloud native security is a [...] multifaceted topic [...] with multiple, diverse components that need to be secured. The cloud platform, the underlying host operating system, the container runtime, the container orchestrator, and then the applications themselves each require specialist security attention" -- Chris Binne, Rory Mccune. Cloud Native Security. (Wiley, 2021)(pp. xix)

### Usage

All security: `./cnti-testsuite security`

----------

### Container socket mounts

#### Overview

This test checks all of the CNFs containers and looks to see if any of them have access to a container runtime socket from the host.
Measurement: Kyverno audit policy [best-practices/disallow-cri-sock-mount](https://github.com/kyverno/policies/tree/release-1.19/best-practices/disallow-cri-sock-mount); the CLI version and policies branch are in the results file's `tools`.
Expectation: Container runtime sockets should not be mounted as volumes

#### Rationale

[Container daemon socket bind mounts](https://kyverno.io/policies/best-practices/disallow_cri_sock_mount/disallow_cri_sock_mount/) allows access to the container engine on the node. This access can be used for privilege escalation and to manage containers outside of Kubernetes, and hence should not be allowed.

Sources: [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Make sure your CNF doesn't mount `/var/run/docker.sock`, `/var/run/containerd.sock` or `/var/run/crio.sock` on any containers.

#### Usage

`./cnti-testsuite container_sock_mounts`

----------

### Privileged Containers

#### Overview

Checks if any containers are running in privileged mode.
Expectation: Containers should not run in privileged mode

#### Rationale

> "... docs describe Privileged mode as essentially enabling “…access to all devices on the host as well as [having the ability to] set some configuration in AppArmor or SElinux to allow the container nearly all the same access to the host as processes running outside containers on the host.” In other words, you should rarely, if ever, use this switch on your container command line." -- Binnie, Chris; McCune, Rory (2021-06-17T23:58:59). Cloud Native Security . Wiley. Kindle Edition.

Sources: [CNTi CBPP-0004, no privilege flag](https://github.com/lfn-cnti/bestpractices/blob/main/doc/cbpps/0004-do-not-run-containers-with-privilege-flag.md); [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Remove privileged capabilities by setting the securityContext.privileged to false. If you must deploy a Pod as privileged, add other restriction to it, such as network policy, Seccomp etc and still remove all unnecessary capabilities.

#### Usage

`./cnti-testsuite privileged_containers`

----------

### External IPs

#### Overview

Checks if the CNF has services with external IPs configured
Measurement: Kyverno audit policy [best-practices/restrict-service-external-ips](https://github.com/kyverno/policies/tree/release-1.19/best-practices/restrict-service-external-ips); the CLI version and policies branch are in the results file's `tools`.
Expectation: A CNF should not run services with external IPs

#### Rationale

Service external IPs can be used for a MITM attack (CVE-2020-8554). Restrict external IPs or limit to a known set of addresses.
See: <https://github.com/kyverno/kyverno/issues/1367>

Sources: [CVE-2020-8554, Kubernetes externalIPs](https://github.com/kubernetes/kubernetes/issues/97076).

#### Remediation

Make sure to not define external IPs in your kubernetes service configuration

#### Usage

`./cnti-testsuite external_ips`

----------

### SELinux Options

#### Overview

Checks if the CNF has escalatory SELinuxOptions configured.
Measurement: Kyverno audit policy [pod-security/baseline/disallow-selinux](https://github.com/kyverno/policies/tree/release-1.19/pod-security/baseline/disallow-selinux), plus the suite's own check-selinux-enabled policy; the CLI version and policies branch are in the results file's `tools`.
Expectation: A CNF should not have any 'seLinuxOptions' configured that allow privilege escalation.

#### Rationale

If [SELinux options](https://kyverno.io/policies/pod-security/baseline/disallow-selinux/disallow-selinux/) is configured improperly it can be used to escalate privileges and should not be allowed.

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline).

#### Remediation

Ensure the following guidelines are followed for any cluster resource that allow SELinux options:

* If the SELinux option `type` is set, it should only be one of the allowed values: `container_t`, `container_init_t`, or `container_kvm_t`.
* SELinux options `user` or `role` should not be set.

#### Usage

`./cnti-testsuite selinux_options`

----------

### Sysctls

#### Overview

Checks the CNF for usage of non-namespaced sysctls mechanisms that can affect the entire host.
Measurement: Kyverno audit policy [pod-security/baseline/restrict-sysctls](https://github.com/kyverno/policies/tree/release-1.19/pod-security/baseline/restrict-sysctls); the CLI version and policies branch are in the results file's `tools`.
Expectation: The CNF should only have "safe" sysctls mechanisms configured, that are isolated from other Pods.

#### Rationale

Sysctls can disable security mechanisms or affect all containers on a host, and should be disallowed except for an allowed "safe" subset. A sysctl is considered safe if it is namespaced in the container or the Pod, and it is isolated from other Pods or processes on the same Node. This test ensures that only those "safe" subsets are specified in a Pod.

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [Kubernetes sysctls](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/).

#### Remediation

The spec.securityContext.sysctls field must be unset or not use.

#### Usage

`./cnti-testsuite sysctls`

----------

### Privilege escalation

#### Overview

Check that the allowPrivilegeEscalation field in the securityContext of each container is set to false.
Measurement: Kubescape control [C-0016](https://hub.armosec.io/docs/c-0016) (Allow privilege escalation) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should not allow privilege escalation

#### Rationale

When [privilege escalation](https://kubernetes.io/docs/concepts/policy/pod-security-policy/#privilege-escalation) is [enabled for a container](https://hub.armo.cloud/docs/c-0016), it will allow setuid binaries to change the effective user ID, allowing processes to turn on extra capabilities.
In order to prevent illegitimate escalation by processes and restrict a process to a NonRoot user mode, escalation must be disabled.

Sources: [Pod Security Standards, restricted](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes); [Kubernetes security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/).

#### Remediation

If your application does not need it, make sure the allowPrivilegeEscalation field of the securityContext is set to false. See more at [ARMO-C0016](https://bit.ly/C0016_privilege_escalation)

#### Usage

`./cnti-testsuite privilege_escalation`

----------

### Symlink file system

#### Overview

This test checks for vulnerable K8s versions and the actual usage of the subPath feature for all Pods in the CNF.
Measurement: Kubescape control [C-0058](https://hub.armosec.io/docs/c-0058) (CVE-2021-25741, using symlink for arbitrary host file system access) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: No vulnerable K8s version being used in conjunction with the subPath feature.

#### Rationale

Due to CVE-2021-25741, subPath or subPathExpr volume mounts can be [used to gain unauthorised access](https://hub.armo.cloud/docs/c-0058) to files and directories anywhere on the host filesystem. In order to follow a best-practice security standard and prevent unauthorised data access, there should be no active CVEs affecting either the container or underlying platform.

Sources: [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final).

#### Remediation

To mitigate this vulnerability without upgrading kubelet, you can disable the VolumeSubpath feature gate on kubelet and kube-apiserver, or remove any existing Pods using subPath or subPathExpr feature.

#### Usage

`./cnti-testsuite symlink_file_system`

----------

### Application credentials

#### Overview

Checks the CNF for sensitive information in environment variables, by using list of known sensitive key names. Also checks for configmaps with sensitive information.
Measurement: Kubescape control [C-0012](https://hub.armosec.io/docs/c-0012) (Applications credentials in configuration files) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Application credentials should not be found in the CNFs configuration files
The scanner matches variables and keys by name. The details name each one found, never its value. One whose value is only a switch (`yes`, `no`, `true`, `false`, `on`, `off` or empty), such as `ALLOW_EMPTY_PASSWORD=yes`, stores no credential: it is listed in the details and does not fail the test. The details also list settings whose names describe credential metadata, such as a token audience, lifetime, or file path. Header values and endpoints with user information, query strings, or fragments remain findings.

#### Rationale

Developers store secrets in the Kubernetes configuration files, such as environment variables in the pod configuration. Such behavior is commonly seen in clusters that are monitored by Azure Security Center.
Attackers who have access to those configurations, by querying the API server or by accessing those files on the developer’s endpoint, can steal the stored secrets and use them.

Sources: [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final); [The Twelve-Factor App, config](https://12factor.net/config).

#### Remediation

Use Kubernetes secrets or Key Management Systems to store credentials.

#### Usage

`./cnti-testsuite application_credentials`

----------

### Host network

#### Overview

Checks if there is a [host network](https://bit.ly/C0041_hostNetwork) attached to any of the Pods in the CNF.
Measurement: Kubescape control [C-0041](https://hub.armosec.io/docs/c-0041) (HostNetwork access) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: The CNF should not have access to the host systems network.

#### Rationale

When a container has the [hostNetwork](https://hub.armo.cloud/docs/c-0041) feature turned on, the container has direct access to the underlying hostNetwork. Hackers frequently exploit this feature to [facilitate a container breakout](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/1/CTR_KUBERNETES%20HARDENING%20GUIDANCE.PDF) and gain access to the underlying host network, data and other integral resources.

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Only connect PODs to the hostNetwork when it is necessary. If not, set the hostNetwork field of the pod spec to false, or completely remove it (false is the default). Allow only those PODs that must have access to host network by design.

#### Usage

`./cnti-testsuite host_network`

----------

### Service account mapping

#### Overview

Check if the CNF is using service accounts that are automatically mapped.
Measurement: Kubescape control [C-0034](https://hub.armosec.io/docs/c-0034) (Automatic mapping of service account) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: The [automatic mapping](https://bit.ly/C0034_service_account_mapping) of service account tokens should be disabled.

#### Rationale

When a pod gets created and a service account wasn't specified, then the default service account will be used. Service accounts assigned in this way can unintentionally give third-party applications root access to the K8s APIs and other application services. In order to follow a zero-trust / fine-grained security methodology, this functionality will need to be explicitly disabled by using the automountServiceAccountToken: false flag. In addition, if RBAC is not enabled, the SA has unlimited permissions in the cluster.

Sources: [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes); [Kubernetes service account tokens](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/).

#### Remediation

Disable automatic mounting of service account tokens to PODs either at the service account level or at the individual POD level, by specifying the automountServiceAccountToken: false. Note that POD level takes precedence.

#### Usage

`./cnti-testsuite service_account_mapping`

----------

### Dedicated service account

#### Overview

Checks that each workload of the CNF runs as a service account other than its namespace's `default`. A workload that names no service account, or names `default`, fails. Several workloads of the CNF may share one account.
Expectation: Every workload of the CNF runs as a service account of its own, not `default`.

#### Rationale

A pod that names no service account runs as its namespace's `default` service account, shared with every other pod that does the same. Its API permissions cannot be scoped to one workload, and the audit log cannot tell the workloads apart. A dedicated service account is what makes least-privilege RBAC possible per workload. `service_account_mapping` checks that the token is not mounted automatically; this test checks which account the pods run as.

Sources: [Kubernetes: Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/); [Kubernetes: RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/); [Red Hat certsuite: access-control-pod-service-account](https://github.com/redhat-best-practices-for-k8s/certsuite/blob/main/CATALOG.md#access-control-pod-service-account).

#### Remediation

Create a ServiceAccount for the workload in the CNF's chart and set `serviceAccountName` to it in the pod template.

#### Usage

`./cnti-testsuite dedicated_service_account`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every workload of the CNF, read from the cluster: the `serviceAccountName` of its pod template (a CronJob's job template, a bare Pod's own spec). The API server mirrors the deprecated `serviceAccount` field into `serviceAccountName`, so a chart using either field is judged by the account it names. A Job that ran to completion and was removed is not judged. Not applicable when the CNF has no workload.
* **Verdicts**: a workload whose `serviceAccountName` is unset, so that its pods run as the namespace's `default` service account, or is set to `default`, fails with the reason. An unset field stays empty on a pod template; on a bare Pod, admission has already filled in `default`, and it fails the same way. Any other account passes, shared or not; the test details list which workload runs as which account.
* **Limits**: only the account's name is judged: not whether the CNF creates it, whether other applications in the namespace run as it too, or which RBAC it is bound to. Whether its token is mounted is judged by [Service account mapping](#service-account-mapping).
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Ingress and Egress blocked

#### Overview

Checks each Pod in the CNF for a defined ingress and egress policy.
Measurement: Kubescape control [C-0030](https://hub.armosec.io/docs/c-0030) (Ingress and Egress blocked) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Ingress and Egress traffic should be blocked on Pods.
The test is not applicable on a cluster whose CNI does not enforce NetworkPolicy (kindnet, flannel): a policy that cannot take effect is not the CNF's doing.

#### Rationale

By default, [no network policies are applied](https://hub.armo.cloud/docs/c-0030) to Pods or namespaces, resulting in unrestricted ingress and egress traffic within the Pod network. In order to [prevent lateral movement](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/1/CTR_KUBERNETES%20HARDENING%20GUIDANCE.PDF) or escalation on a compromised cluster, administrators should implement a default policy to deny all ingress and egress traffic.
This will ensure that all Pods are isolated by default and further policies could then be used to specifically relax these restrictions on a case-by-case basis.

Sources: [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes); [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/); [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final).

#### Remediation

By default, you should disable or restrict Ingress and Egress traffic on all pods.

#### Usage

`./cnti-testsuite ingress_egress_blocked`

----------

### Insecure capabilities

#### Overview

Checks the CNF for any usage of insecure capabilities using the following [deny list](https://man7.org/linux/man-pages/man7/capabilities.7.html)
Measurement: Kubescape control [C-0046](https://hub.armosec.io/docs/c-0046) (Insecure capabilities) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should not have insecure capabilities enabled.

#### Rationale

Giving [insecure](https://hub.armo.cloud/docs/c-0046) and unnecessary capabilities for a container can increase the impact of a container compromise.

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Remove all insecure capabilities which aren’t necessary for the container.

#### Usage

`./cnti-testsuite insecure_capabilities`

----------

### Non-root containers

#### Overview

Checks that no container of the CNF runs as root. A container whose manifest does not rule root out is checked on its node: it fails when its process runs as user or group 0, or cannot be observed. One observed running as non-root passes, with a remediation to declare it.
Expectation: Containers should run with non-root user and group, and should declare it so the kubelet enforces it.

#### Rationale

Container engines allow containers to run applications as a non-root user with non-root group membership. Typically, this non-default setting is configured when the container image is built. Alternatively, Kubernetes can load containers into a Pod with SecurityContext:runAsUser specifying a non-zero user. While the runAsUser directive effectively forces non-root execution at deployment, [NSA and CISA encourage developers](https://hub.armo.cloud/docs/c-0013) to build container applications to execute as a non-root user. Having non-root execution integrated at build time provides better assurance that applications will function correctly without root privileges.

Sources: [CNTi CBPP-0002, non-root containers](https://github.com/lfn-cnti/bestpractices/blob/main/doc/cbpps/0002-no-root-in-containers.md); [Pod Security Standards, restricted](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

If your application does not need root privileges, build the image to run as a non-root user and declare it in the manifest: set `runAsNonRoot: true` and `runAsGroup`, or set `runAsUser` and `runAsGroup` to IDs of 1000 or higher, under the pod or container securityContext. The declaration makes the kubelet refuse the container if a later image runs as root.

#### Usage

`./cnti-testsuite non_root_containers`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the containers and init containers of the CNF's workloads, as Kubescape reads them from the cluster in its scan of the NSA framework; findings for resources outside the CNF are left out. Not applicable when the CNF has no workload.
* **Verdicts**: Kubescape control [C-0013](https://hub.armosec.io/docs/c-0013) (Non-root containers) flags a container whose manifest does not rule root out: neither `runAsNonRoot: true` nor a non-zero `runAsUser` is set, or `runAsGroup` is unset or 0, at the container or the pod level, the container's value taking precedence. Each flagged container is then observed on its node through cluster-tools: the effective user and group of its first process are read from `/proc/PID/status`. Observed with a non-zero user and group, it passes, and the details list it as observed as non-root but not declared, with the missing fields as remediation. Observed as uid 0 or gid 0, it fails with the user, the group and the field Kubescape names. A scan that produced no report makes the test an error with Kubescape's reason.
* **Verdicts**: a flagged container that cannot be observed fails; the rule for [Containers that cannot be inspected](#containers-that-cannot-be-inspected) does not apply here. That covers a container that is not started or not ready, every init container (it has finished), the containers of a CronJob and of a Job whose pods have completed, and a container on a node where cluster-tools cannot read the process. A flagged workload for which Kubescape names no field fails with its alert message.
* **Limits**: supplementary groups are not read. When several pods of a workload run a container of the same name, one observation judges them all. Whether privilege escalation is allowed is judged by [Privilege escalation](#privilege-escalation). The scanner and regolibrary versions are in the results file's `tools`.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Host PID/IPC privileges

#### Overview

Checks if containers are running with hostPID or hostIPC privileges.
Read more at [ARMO-C0038](https://bit.ly/3nGvpIQ)
Measurement: Kubescape control [C-0038](https://hub.armosec.io/docs/c-0038) (Host PID/IPC privileges) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should not have hostPID and hostIPC privileges

#### Rationale

Containers should be isolated from the host machine as much as possible. The [hostPID and hostIPC](https://hub.armo.cloud/docs/c-0038) fields in deployment yaml may allow cross-container influence and may expose the host itself to potentially malicious or destructive actions. This control identifies all PODs using hostPID or hostIPC privileges.

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Apply least privilege principle and remove hostPID and hostIPC from the yaml configuration privileges unless they are absolutely necessary.

#### Usage

`./cnti-testsuite host_pid_ipc_privileges`

----------

### Seccomp profile

#### Overview

Checks that every container of the CNF runs under a seccomp profile: its own `securityContext.seccompProfile`, or the pod's. A profile of type `RuntimeDefault` or `Localhost` passes; `Unconfined`, or no profile at all, fails, reported per container.
Expectation: Every container runs under a seccomp profile.

#### Rationale

Seccomp filters the system calls a process may make, so a compromised container cannot reach kernel surface its workload never needs. The Kubernetes [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) require a `RuntimeDefault` or `Localhost` profile at the restricted level, and the [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes) (5.7.2) recommends the runtime default for all containers. Unlike the broader `linux_hardening` check, this test asks for that one control alone, so a CNF can be judged on the requirement the standards actually state.

#### Remediation

Set `securityContext.seccompProfile.type: RuntimeDefault` on the pod, so every container inherits it, or per container; use `Localhost` with a profile of your own where the runtime default is too permissive or too strict.

#### Usage

`./cnti-testsuite seccomp_profile`

----------

### Linux hardening

#### Overview

Check if there are AppArmor, Seccomp, SELinux or Capabilities defined in the securityContext of the CNF's containers and pods.
Read more at [ARMO-C0055](https://bit.ly/2ZKOjpJ).
Measurement: Kubescape control [C-0055](https://hub.armosec.io/docs/c-0055) (Linux hardening) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Security services are being used to harden application.

#### Rationale

In order to reduce the attack surface, it is recommend, when it is possible, to harden your application using [security services](https://hub.armo.cloud/docs/c-0055) such as SELinux®, AppArmor®, and seccomp. Starting from Kubernetes version 1.22, SELinux is enabled by default.

Sources: [Pod Security Standards, restricted](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes); [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final).

#### Remediation

Use AppArmor, Seccomp, SELinux and Linux Capabilities mechanisms to restrict containers abilities to utilize unwanted privileges.

#### Usage

`./cnti-testsuite linux_hardening`

----------

### CPU limits

#### Overview

Check if there is a ‘containers[].resources.limits.cpu’ field defined for all pods in the CNF.
Measurement: Kubescape control [C-0270](https://hub.armosec.io/docs/c-0270) (Ensure CPU limits are set) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should have cpu limits defined

#### Rationale

Every container [should have a limit set for the CPU available for it](https://hub.armo.cloud/docs/c-0270) set for every container or a namespace to prevent resource exhaustion. This test identifies all the Pods without CPU limit definitions by checking their yaml definition file as well as their namespace LimitRange objects. It is also recommended to use ResourceQuota object to restrict overall namespace resources, but this is not verified by this test.

Sources: [Kubernetes resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

#### Remediation

Define LimitRange and ResourceQuota policies to limit CPU usage for namespaces or in the deployment/POD yamls.

#### Usage

`./cnti-testsuite cpu_limits`

----------

### Memory limits

#### Overview

Check if there is a ‘containers[].resources.limits.memory’ field defined for all pods in the CNF.
Measurement: Kubescape control [C-0271](https://hub.armosec.io/docs/c-0271) (Ensure memory limits are set) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should have memory limits defined

#### Rationale

Every container [should have a limit set for the memory available for it](https://hub.armo.cloud/docs/c-0271) set for every container or a namespace to prevent resource exhaustion. This test identifies all the Pods without memory limit definitions by checking their yaml definition file as well as their namespace LimitRange objects. It is also recommended to use ResourceQuota object to restrict overall namespace resources, but this is not verified by this test.

Sources: [Kubernetes resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Define LimitRange and ResourceQuota policies to limit memory usage for namespaces or in the deployment/POD yamls.

#### Usage

`./cnti-testsuite memory_limits`

----------

### Resource requests

#### Overview

Checks that every container of the CNF's workloads sets `resources.requests.cpu` and `resources.requests.memory`. Init containers are judged separately, by `init_container_requests`. A request that Kubernetes fills in, from the container's own limit or from a namespace `LimitRange` default, counts as set and is named in the details. The values are not judged.
Expectation: Every container requests CPU and memory.

#### Rationale

The scheduler places a pod by its requests: a container without one is placed as if it needed nothing. A pod none of whose containers requests anything is in the [BestEffort QoS class](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/), the first the kubelet [evicts](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/#pod-selection-for-kubelet-eviction) when a node runs short of memory. A request copied from a limit passes, but is named, because it is rarely the size the workload needs: it reserves the peak. Whether a request is the right size is a measurement question, an idle and a loaded run, not a manifest one, so the test does not judge it.

Sources: [Kubernetes resource management: requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#requests-and-limits); [Pod Quality of Service classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/).

#### Remediation

Set `resources.requests.cpu` and `resources.requests.memory` on every container, sized from a measured idle and loaded run. Where a chart leaves sizing to the user, ship reasonable defaults rather than none.

#### Usage

`./cnti-testsuite resource_requests`

----------

### Init container requests

#### Overview

Checks that every init container of the CNF's workloads sets `resources.requests.cpu` and `resources.requests.memory`, with the same rules as `resource_requests`: a request filled in from the container's limit or from a namespace `LimitRange` default counts as set and is named. Not applicable when no workload has init containers.
Expectation: Every init container requests CPU and memory.

#### Rationale

An init container runs before the workload's containers and to completion, so a missing request weighs less than on a workload container: the pod is scheduled by the larger of its containers' total and its largest init container, and its [QoS class](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) stays Burstable while the other containers request. The init container still runs unsized, and a namespace with a [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/) on requests rejects any pod in which a container, init containers included, sets none.

Sources: [Kubernetes init containers: resource sharing](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/#resource-sharing-within-containers); [Resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/).

#### Remediation

Set `resources.requests.cpu` and `resources.requests.memory` on every init container. A wait or copy step needs little; a migration or data load should be sized like a workload container.

#### Usage

`./cnti-testsuite init_container_requests`

----------

### Immutable File Systems

#### Overview

Checks whether the readOnlyRootFilesystem field in the SecurityContext is set to true.
Read more at [ARMO-C0017](https://bit.ly/3pSMtxK)
Measurement: Kubescape control [C-0017](https://hub.armosec.io/docs/c-0017) (Immutable container filesystem) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should use an immutable file system when possible.

#### Rationale

Mutable container filesystem can be abused to gain malicious code and data injection into containers. By default, containers are permitted unrestricted execution within their own context.
An attacker who has access to a container, [can create files](https://hub.armo.cloud/docs/c-0017) and download scripts as they wish, and modify the underlying application running on the container.

Sources: [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Set the filesystem of the container to read-only when possible. If the containers application needs to write into the filesystem, it is possible to mount secondary filesystems for specific directories where application require write access.

#### Usage

`./cnti-testsuite immutable_file_systems`

----------

### HostPath Mounts

#### Overview

Checks that no pod of the CNF declares a hostPath volume. Any hostPath volume fails the test, read-only ones included: a host directory mounted into a container is a path to the underlying host either way.
Expectation: Containers should not have hostPath mounts

#### Rationale

[hostPath mount](https://hub.armo.cloud/docs/c-0006) can be used by attackers to get access to the underlying host and thus break from the container to the host. (See “3: Writable hostPath mount” for details).

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [Kubernetes volumes](https://kubernetes.io/docs/concepts/storage/volumes/); [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final).

#### Remediation

Refrain from using a hostPath mount.

#### Usage

`./cnti-testsuite hostpath_mounts`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the pod specs of the CNF's workloads, CronJobs' job templates included, as Kubescape reads them from the cluster; findings for resources outside the CNF are left out. Not applicable when the CNF has no workload.
* **Verdicts**: Kubescape control [C-0048](https://hub.armosec.io/docs/c-0048) (HostPath mount), scanned on its own, flags every volume with a `hostPath`, whether or not a container mounts it; the finding names the volume and each container or init container that mounts it. No path and no type is exempt. A scan that produced no report makes the test an error with Kubescape's reason. The scanner and regolibrary versions are in the results file's `tools`.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### SBOM available

#### Overview

Checks that the image of every regular container of the CNF (init and ephemeral containers are not checked) has an SBOM (Software Bill of Materials) published with it in its registry. An image without one fails. An image the test cannot read is not a failure: when no image fails and one could not be read, the test is skipped.
Expectation: Every container image has a discoverable SBOM.

#### Rationale

An SBOM lets operators inventory the components inside a CNF's images and respond to newly disclosed vulnerabilities in those components. Publishing it with the image (rather than out of band) means consumers can find it from the image reference alone.

Sources: [CISA Software Bill of Materials (SBOM)](https://www.cisa.gov/sbom); [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final).

#### Remediation

Publish an SBOM for each container image — attach it with `docker buildx build --sbom=true` (an OCI attestation manifest with an SPDX or CycloneDX layer) or `cosign attest --type spdxjson` (a cosign attestation). The deprecated `cosign attach sbom` / `.sbom` tag is checked as a fallback.

#### Usage

`./cnti-testsuite sbom_available`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the image of every container of the CNF's workloads, read from the cluster; init and ephemeral containers are not judged. Each distinct image is inspected once, as published in its registry, not in a source tree. Not applicable when the CNF declares no container image.
* **Configuration**: `image_registry_fqdns` in `cnti-testsuite.yaml`: maps a registry host in an image reference to the address the test reaches it at.
* **Verdicts**: skopeo, in the cluster-tools pod, reads the image's manifest (`skopeo inspect --raw`) and looks for an SBOM in three places, in order: (1) a BuildKit/OCI attestation manifest listed in the image index, with a layer whose `in-toto.io/predicate-type` is SPDX (`https://spdx.dev/Document`) or CycloneDX (`https://cyclonedx.org/bom`); a provenance-only attestation does not count; (2) a cosign attestation tag (`REPO:sha256-DIGEST.att`) with a layer whose `predicateType` annotation is SPDX or CycloneDX; (3) the deprecated cosign `.sbom` tag, whose presence counts. The cosign tags are found by the image's digest, from the reference or from the registry. The details say where each SBOM was found.
* **Verdicts**: an image with none of them fails, naming each container that runs it. An image whose manifest cannot be read or parsed (a private registry, a network error) is named with the reason and is not a finding; the test is skipped when no image fails and at least one could not be read. The test is also skipped when cluster-tools is not ready or cannot inspect containers on every node.
* **Limits**: skopeo is given no registry credentials, so an image that needs them cannot be read. The SBOM's content is not checked, only its predicate type.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

## Category: Configuration Tests

Configuration should be managed in a declarative manner, using [ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/), [Operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/), or other [declarative interfaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/#understanding-kubernetes-objects).

Declarative APIs for an immutable infrastructure are anything that configures the infrastructure element. This declaration can come in the form of a YAML file or a script, as long as the configuration designates the desired outcome, not how to achieve said outcome.

> "Because it describes the state of the world, declarative configuration does not have to be executed to be understood. Its impact is concretely declared. Since the effects of declarative configuration can be understood before they are executed, declarative configuration is far less error-prone." -- Hightower, Kelsey; Burns, Brendan; Beda, Joe. Kubernetes: Up and Running: Dive into the Future of Infrastructure (Kindle Locations 183-186). Kindle Edition*

### Usage

All configuration: `./cnti-testsuite configuration`

----------

### Hugepages volumes

#### Overview

Checks that every hugepages `emptyDir` volume of the CNF is backed by a hugepages request of the same page size in its pod; without one, the kubelet does not mount the volume and the pod never starts. A volume without a matching request fails. A CNF with no hugepages volume is not applicable.
Expectation: Every hugepages volume of the CNF is backed by a hugepages request of the same size in its pod.

#### Rationale

DPDK-style and other latency-sensitive network functions surface hugepages to the workload through an `emptyDir` volume with a `HugePages` medium. The API server accepts a hugepages volume that no request in the pod backs, but the kubelet then refuses to mount it: the pod stays in `ContainerCreating` with a `FailedMount ... there is no resource request for huge pages` event, which is hard to diagnose. This test catches the mismatch in the manifest first.

Sources: [Manage HugePages](https://kubernetes.io/docs/tasks/manage-hugepages/scheduling-hugepages/); [emptyDir volumes](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir).

#### Remediation

Back each hugepages `emptyDir` volume with a hugepages request in the pod: a `HugePages-<size>` medium needs a container (or init container) requesting `hugepages-<size>`, and a size-less `HugePages` medium needs the pod to request hugepages in a single page size.

#### Usage

`./cnti-testsuite hugepages_volumes`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the workloads of the CNF's installed manifest, as rendered, not the cluster's objects; each workload's pod spec is judged once. A volume is a hugepages volume when its `emptyDir` medium starts with `HugePages`. A container that requests hugepages without such a volume is legitimate and not judged. Not applicable when no workload declares a hugepages volume.
* **Verdicts**: the page sizes a pod requests are gathered from the `requests` and `limits` of all its containers and init containers (a hugepages limit with no request is valid: Kubernetes defaults the request from it). A `HugePages-SIZE` medium needs a request for `hugepages-SIZE`. A size-less `HugePages` medium needs the pod to request hugepages in exactly one page size: none, or more than one, is a finding. Each finding names the workload and the volume.
* **Limits**: page sizes are compared as written, so `HugePages-1Gi` is not backed by `hugepages-1024Mi`. The nodes' hugepages capacity is not checked.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Default namespaces

#### Overview

Checks if any of the CNF's resources are deployed in the default namespace.
Measurement: Kyverno audit policy [best-practices/disallow-default-namespace](https://github.com/kyverno/policies/tree/release-1.19/best-practices/disallow-default-namespace); the CLI version and policies branch are in the results file's `tools`.
Expectation: Resources should not be deployed in the default namespace.

#### Rationale

Namespaces provide a way to segment and isolate cluster resources across multiple applications and users.
As a best practice, workloads should be isolated with Namespaces and not use the default namespace.

Sources: [Kubernetes namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

Ensure that your CNF is configured to use a Namespace and is not using the default namespace.

#### Usage

`./cnti-testsuite default_namespace`

----------

### Latest tag

#### Overview

Checks if the CNF is using a 'latest' tag instead of a semantic version.
Measurement: Kyverno audit policy [best-practices/disallow-latest-tag](https://github.com/kyverno/policies/tree/release-1.19/best-practices/disallow-latest-tag); the CLI version and policies branch are in the results file's `tools`.
Expectation: The CNF should use an immutable tag that maps to a symantic version of the application.

#### Rationale

You should [avoid using the :latest tag](https://kubernetes.io/docs/concepts/containers/images/) when deploying containers in production as it is harder to track which version of the image is running and more difficult to roll back properly.

Sources: [Kubernetes configuration best practices](https://kubernetes.io/docs/concepts/configuration/overview/); [Kubernetes images](https://kubernetes.io/docs/concepts/containers/images/).

#### Remediation

Pin every container image to a release tag that names a version, or to a digest. Remove `latest`, untagged images and moving tags such as `stable` or `main`, which are not guaranteed to point to the same build twice and cannot be tracked or rolled back.

#### Usage

`./cnti-testsuite latest_tag`

----------

### Require labels

#### Overview

Checks if the CNF validates that the label `app.kubernetes.io/name` is specified with some value.
Measurement: Kyverno audit policy [best-practices/require-labels](https://github.com/kyverno/policies/tree/release-1.19/best-practices/require-labels); the CLI version and policies branch are in the results file's `tools`.
Expectation: Checks if pods are using the 'app.kubernetes.io/name' label

#### Rationale

Defining and using labels help identify semantic attributes of your application or Deployment. A common set of labels allows tools to work collaboratively, while describing objects in a common manner that all tools can understand. You should use recommended labels to describe applications in a way that can be queried.

Sources: [Kubernetes recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/).

#### Remediation

Make sure to define `app.kubernetes.io/name` label under metadata for your CNF.

#### Usage

`./cnti-testsuite require_labels`

----------

### Versioned tag

#### Overview

Checks that the image of every regular container of the CNF (init and ephemeral containers are not checked) is referenced by digest or by a tag that names a version. An untagged image, the `latest` tag, or a tag without a digit such as `stable` or `main` fails. A versioned tag can still move to another build.
Expectation: Every container image is referenced by a digest or a versioned tag.

#### Rationale

You should [avoid using the :latest tag](https://kubernetes.io/docs/concepts/containers/images/) when deploying containers in production as it is harder to track which version of the image is running and more difficult to roll back properly.

Sources: [Kubernetes configuration best practices](https://kubernetes.io/docs/concepts/configuration/overview/); [Kubernetes images](https://kubernetes.io/docs/concepts/containers/images/).

#### Remediation

When specifying container images, always specify a tag and ensure to use an immutable tag that maps to a specific version of an application Pod. Remove any usage of the `latest` tag, as it is not guaranteed to be always point to the same version of the image.

#### Usage

`./cnti-testsuite versioned_tag`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the image reference of every container of the CNF's workloads, read from the cluster; init and ephemeral containers are not judged. A Job that ran to completion and was removed is not judged. Not applicable when the CNF has no workload.
* **Verdicts**: an image is versioned when it is pinned by a `@sha256:` digest, or by a tag that is present, is not `latest` and names a version, which for the test means it contains a digit (`1.2.3`, `v2`, `6.0.2-debian-11-r0`, `20240101`). A registry port (`registry:5000/org/image`) is not a tag. Each container that is not versioned is a finding with its image and the reason: no tag (implicitly `latest`), the `latest` tag, or a moving tag that names no version. The details list the versioned ones.
* **Limits**: the registry is not read, so a tag that contains a digit passes even when it moves (`ubuntu-24.04-latest`).
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### NodePort not used

#### Overview

Checks the CNF for any associated K8s Services that configured to expose the CNF by using a nodePort.
Expectation: The nodePort configuration field is not found in any of the CNF's services.

#### Rationale

Using node ports ties the CNF to a specific node and therefore makes the CNF less portable and scalable.

Sources: [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/).

#### Remediation

Review all Helm Charts & Kubernetes Manifest files for the CNF and remove all occurrences of the nodePort field in your configuration. Alternatively, configure a service or use another mechanism for exposing your container.

#### Usage

`./cnti-testsuite nodeport_not_used`

----------

### HostPort not used

#### Overview

Checks the CNF's workload resources for any containers using the hostPort configuration field to expose the application.
Expectation: The hostPort configuration field is not found in any of the defined containers.

#### Rationale

Using host ports ties the CNF to a specific node and therefore makes the CNF less portable and scalable.

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [Kubernetes configuration best practices](https://kubernetes.io/docs/concepts/configuration/overview/).

#### Remediation

Review all Helm Charts & Kubernetes Manifest files for the CNF and remove all occurrences of the hostPort field in your configuration. Alternatively, configure a service or use another mechanism for exposing your container.

#### Usage

`./cnti-testsuite hostport_not_used`

----------

### Hardcoded IP addresses in K8s runtime configuration

#### Overview

Checks the CNF's Kubernetes resources, and the files its ConfigMaps carry, for hardcoded IPv4 addresses. Each address found fails the test, except CIDR ranges, `127.0.0.1`, `0.0.0.0` and the addresses the CNF lists in `hardcoded_ip_exceptions`.
Expectation: No hardcoded IP addresses are found in the CNF's Kubernetes resources unless they are in CIDR format or explicitly listed in `hardcoded_ip_exceptions`.

#### Rationale

Using a hard coded IP in a CNF's configuration designates *how* (imperative) a CNF should achieve a goal, not *what* (declarative) goal the CNF should achieve.

Sources: [The Twelve-Factor App, config](https://12factor.net/config); [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/).

#### Remediation

Review all Helm Charts & Kubernetes Manifest files of the CNF and look for any hardcoded usage of ip addresses. If any are found, you will need to use an operator or some other method to abstract the IP management out of your configuration in order to pass this test.

#### Usage

`./cnti-testsuite hardcoded_ip_addresses_in_k8s_runtime_configuration`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every resource of the CNF's installed manifest, not only its workloads: the rendered chart or manifests, with the workloads found by label or created by an operator for the CNF's custom resources (read without their status). The manifest is scanned line by line. CustomResourceDefinitions are not scanned: they are schemas whose descriptions carry RFC section numbers and OIDs, not configuration. The files a ConfigMap carries in its `data` are read file line by file line; comment lines (whose first non-blank character is `#`, such as the commented-out defaults many config files ship with) are not configuration and are ignored. The ConfigMap's other lines, its metadata and `binaryData`, are not scanned. Comment lines elsewhere in the manifest are scanned.
* **Configuration**: `hardcoded_ip_exceptions` under `common` in the [CNF configuration](https://github.com/lfn-cnti/testsuite/blob/main/docs/CNTI_TESTSUITE_YAML_USAGE.md), one `- ip: ADDRESS` entry per address: addresses justified by application logic, which are excluded from violation reports.
* **Verdicts**: four dot-separated numbers count as an address only when each is an octet (0 to 255). An address followed by a prefix length (`10.0.0.0/8`) is CIDR notation and does not cause the test to fail, and `127.0.0.1` and `0.0.0.0` are always allowed. Each other address is a finding that names the resource it sits in, its line in the manifest and the line's text.
* **Limits**: IPv6 addresses are not detected. A dotted number with four parts, such as a version `1.2.3.4`, is taken for an address. The line scan stops at the first line that contains `NOTES:`, so the manifest's lines after it are not scanned; ConfigMap files are read in full.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Secrets used

#### Overview

Checks that every Secret in the namespaces of the CNF's workloads is read by one of them, and that every Secret a workload requires exists. An unread Secret or a missing required one fails. A CNF that has no Secret and reads none is not applicable.
Expectation: The CNF keeps its sensitive data in Secrets, and every Secret it ships is read by one of its workloads.

#### Rationale

If a CNF uses kubernetes K8s secrets instead of unencrypted environment variables or configmaps, there is [less risk of the Secret (and its data) being exposed](https://kubernetes.io/docs/concepts/configuration/secret/) during the workflow of creating, viewing, and editing Pods.

Sources: [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/); [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final); [The Twelve-Factor App, config](https://12factor.net/config).

#### Remediation

Remove any sensitive data stored in configmaps, environment variables and instead utilize K8s Secrets for storing such data.
Alternatively, you can use an operator or some other method to abstract hardcoded sensitive data out of your configuration.
A Secret the CNF ships but no workload reads is either dead data in the namespace or a sign that the workload takes its credentials from somewhere else: read it from a workload, or stop shipping it. A reference to a Secret that does not exist must name an existing one, or declare itself `optional`.

#### Usage

`./cnti-testsuite secrets_used`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the CNF's workloads, read from the cluster, and the Secrets in each namespace where one of them runs. Every Secret there counts as shipped by the CNF, whoever created it, except service account tokens (`kubernetes.io/service-account-token`), registry credentials (`kubernetes.io/dockercfg`, `kubernetes.io/dockerconfigjson`) and Helm's release records (`helm.sh/release.v1`). Not applicable when no Secret is shipped and no workload reads one, or when the CNF has no workload.
* **Verdicts**: a workload reads a Secret through a `secret` volume or a projected volume's secret source that one of its containers mounts (a volume no container mounts reaches no process), an env `secretKeyRef` or an `envFrom` `secretRef` of any of its containers, init and ephemeral ones included, or an `imagePullSecrets` entry. A shipped Secret that no workload in its namespace reads fails. A reference to a Secret that does not exist in the namespace fails, unless it is `optional: true`; an `imagePullSecrets` entry is never required. The details list which workload reads which Secret.
* **Limits**: only the pod spec counts as reading: a Secret that an application or an operator reads through the Kubernetes API, or that only a ServiceAccount, an Ingress or a custom resource names, is unread. A Secret another tool creates in the CNF's namespace (a cert-manager certificate, for example) counts as shipped. Whether sensitive data sits in ConfigMaps or environment variables instead of Secrets is not checked.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Immutable configmap

#### Overview

Checks that every ConfigMap the CNF's workloads use as a volume or in a container's environment variables is immutable. Each mutable one is a finding, with the workload and container that use it. A cluster that does not enforce immutable ConfigMaps makes the test not applicable.
Expectation: Immutable configmaps are being used for non-mutable data.

#### Rationale

For clusters that extensively use ConfigMaps (at least tens of thousands of unique ConfigMap to Pod mounts),
[preventing changes](https://kubernetes.io/docs/concepts/configuration/configmap/#configmap-immutable)
to their data has the following advantages:

* protects you from accidental (or unwanted) updates that could cause applications outages
* improves performance of your cluster by significantly reducing load on kube-apiserver, by closing watches for ConfigMaps marked as immutable.

Sources: [Immutable ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/#configmap-immutable).

#### Remediation

Use immutable configmaps for any non-mutable configuration data.

#### Usage

`./cnti-testsuite immutable_configmap`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: the CNF's workloads, read from the cluster, and the ConfigMaps in each one's namespace. A workload uses a ConfigMap through a `configMap` volume of its pod spec, whether or not a container mounts it, or through a `valueFrom.configMapKeyRef` in the env of one of its regular containers. An `envFrom` `configMapRef`, a projected volume's ConfigMap source and init containers are not checked, and a reference to a ConfigMap that does not exist is not judged. Not applicable when the CNF has no workload.
* **Verdicts**: the cluster is first probed with an immutable ConfigMap that must reject a change; a cluster that accepts it does not enforce immutability, and the test is not applicable there. A used ConfigMap without `immutable: true` is then a finding for each container that mounts it or reads it in its env, and a mutable volume is also reported for the workload, without a container, when a container does not mount it. A CNF whose workloads use no ConfigMap passes.
* **Side effects**: the probe is the ConfigMap `cnti-immutable-configmap-probe` in the suite's `cnti-testsuite` namespace, created, changed and deleted again; no resource of the CNF is changed.
* **Common rules**: [Jobs and CronJobs](#jobs-and-cronjobs).

</details>

----------

### Kubernetes Alpha APIs

#### Overview

Checks that the CNF declares no resource with an alpha version of a Kubernetes API, and no CustomResourceDefinition that serves a Kubernetes API in alpha versions only. Each such resource fails. A project's own API groups are not judged: their alpha versions are the project's own versioning.
Expectation: CNF should not use Kubernetes alpha APIs

#### Rationale

If a CNF uses alpha or undocumented APIs, the CNF is tightly coupled to an unstable platform

Sources: [Kubernetes API deprecation policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Make sure your CNFs are not utilizing any Kubernetes alpha APIs. You can learn more about Kubernetes API versioning [here](https://bit.ly/k8s_api).

#### Usage

`./cnti-testsuite alpha_k8s_apis`

#### Details

<details>
<summary>How the test works in detail</summary>

* **Scope**: every resource of the CNF's installed manifest: the rendered chart or manifests, Helm hooks excluded, with the workloads found by label or created by an operator, and the CustomResourceDefinitions the install read from the cluster for the CNF's custom resources. A CNF with no such resource passes; the test is never not applicable.
* **Verdicts**: a Kubernetes API is one in a group Kubernetes governs: the core group (`v1`), the legacy groups without a domain (`apps`, `batch`, `autoscaling`, `policy`, `extensions`, `events`) and `*.k8s.io`, the SIG APIs delivered as CRDs included (a `gateway.networking.k8s.io/v1alpha2` route of the Gateway API's experimental channel is a finding). A project's own API group (`keda.sh`, `external-secrets.io`, a `*.x-k8s.io` sandbox group) is not judged: its `v1alpha1` versions are the project's own versioning, not a Kubernetes alpha feature. A resource of a Kubernetes group is a finding when the version in its `apiVersion` contains `alpha`. A CustomResourceDefinition of a Kubernetes group is a finding when every version it serves is alpha; a version with `served: false` does not count.
* **Limits**: beta versions are not judged, and neither are alpha fields or feature gates within a stable API version; [Deprecated K8s Features](#deprecated-k8s-features) judges deprecated APIs.

</details>

----------

### Operator installed

#### Overview

This test checks if the CNF installs an Operator using the [Operator Lifecycle Manager (OLM)](https://olm.operatorframework.io/). It scans the CNF's resources for OLM Subscriptions and verifies that each Subscription resolves to a ClusterServiceVersion (CSV) that reaches the `Succeeded` phase, and that every Deployment the CSV's install strategy creates becomes ready.
Expectation: If the CNF ships an Operator, it is installed through OLM, its ClusterServiceVersion reports a successful installation and its operator Deployments are ready. A Subscription that never resolves, a CSV that does not succeed or an operator Deployment that is not ready is reported as a failure, with each affected resource listed under the test's impacted resources. If no Subscription is found, the test is not applicable.

#### Rationale

[Operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/) encode operational knowledge for a workload in software, enabling declarative, self-healing lifecycle management. Installing Operators through OLM makes their installation, upgrade, and dependency handling declarative and verifiable instead of relying on manual or ad-hoc installation steps.

Sources: [Kubernetes operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/).

#### Remediation

If your CNF uses an Operator, package it for the Operator Lifecycle Manager and install it via an OLM Subscription, so that the resulting ClusterServiceVersion reports a successful installation. Ensure the Subscription and its target namespace are part of the CNF's resources.

#### Usage

`./cnti-testsuite operator_installed`

----------

### Exclusive CPUs

#### Overview

The CNF names its latency-sensitive workloads, and the containers within them that need pinned CPUs, under `latency_sensitive` in a deployment's `cnti-testsuite.yaml` (a deployment entry can be a whole chart with many workloads, so the sensitive ones are named individually):

```yaml
deployments:
  helm_charts:
    - name: free5gc
      latency_sensitive:
        - {kind: Deployment, name: free5gc-upf, containers: [upf]}
```

Expectation: each named workload's pods are Guaranteed QoS (so the kubelet can assign exclusive CPUs at all), and each named container requests a whole number of CPUs (e.g. `2` or `1000m`, not `500m`). Guaranteed is decided by every container, init containers included; a container that is not named may request a fraction and run on the shared pool without failing the test. A CNF that names no latency-sensitive workload is reported as N/A. When nothing can be measured — a named workload that is absent or has no pods, a pod without a QoS class yet, or a named container the pod does not have — the test is `skipped` with a remediation.
Measurement: the test reads the named workloads' live pods and uses `status.qosClass` (which the API server sets with request-from-limit defaulting and any LimitRange applied) for the Guaranteed check, and the pods' defaulted cpu requests for the whole-CPU check.

#### Rationale

Latency-sensitive network functions (DPDK, RAN) depend on dedicated CPUs. The kubelet static CPU manager policy pins CPUs only for a Guaranteed-QoS pod's containers that request whole (integer) CPUs; a fractional request on a container that needs pinning, or a pod that is not Guaranteed, silently leaves the workload on shared CPUs, hurting tail latency. A misconfiguration is accepted by the API server and runs without any warning, so the test surfaces it.

Sources: [CPU Management Policies (kubelet static policy)](https://kubernetes.io/docs/tasks/administer-cluster/cpu-management-policies/); [Configure Quality of Service for Pods (Guaranteed QoS)](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/).

#### Remediation

For each latency-sensitive workload make its pods Guaranteed (set cpu and memory requests equal to their limits on every container, init included) and give the pinned containers whole-CPU requests (e.g. `2` or `1000m`), so the static CPU manager can assign exclusive CPUs.

#### Usage

`./cnti-testsuite exclusive_cpus`

----------

----------

## Common rules

Rules that several tests share. A test's Details links to the ones that apply to it.

----------

### Rollout tests

Rolling update, Rolling version change, Rolling downgrade and Rollback move the CNF to the version before the installed one, or to the tag configured for the test, and each judges one step of that change, as its Details say: the upgrade back, the move down, or Rollback's `helm rollback` and `kubectl rollout undo`. They share these rules.

* **Two paths**: a chart installed from a Helm repository or an OCI registry (`helm_charts`) is moved as a release, image and pod spec together, as an upgrade does: to its previous version with `helm upgrade` and the configured values. Workloads the CNF ships from a chart directory or from manifests have no previous release to install and are moved one image at a time with [kubectl set image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-).
* **The previous chart version**: `previous_chart_version` when configured, else the chart version before the installed one in the repository: the closest older version of the same form. A version that ships the same app version as the installed chart is a chart-only change, so the search goes on to the closest older one with another app version.
* **The previous image**: the container's tag for the test in the `container_names` section of `cnti-testsuite.yaml` (`rolling_update_test_tag`, `rolling_version_change_test_tag`, `rolling_downgrade_test_tag`, `rollback_from_tag`), used as given: it only has to differ from the deployed tag and is not checked to be older; else the image's previous release in its registry, named in the details: the closest older tag of the same form as the deployed one (`v4.3.0` takes `v4.2.3`, never `v4.3.0-rc1`; a commit hash in the tag is a label, so `…-20261016_52af3689` takes `…-20261015_de11750b`).
* **Left out with a remediation**: a release whose older versions all ship the installed app version; a configured `previous_chart_version` that is not older than the installed one; a container whose configured tag is the one it already runs (that rolls nothing out); a container with no tag configured whose tag names no version (`latest`, `stable`, or a tag ending in `-latest`) or that has no older release.
* **Version skew**: a previous image taken from the registry that crash-loops under the pod spec the current chart renders is version skew, which no upgrade produces (an upgrade moves image and spec together). The workload is named in the details with the reason and not judged, and a CNF whose workloads all do that is not applicable. A configured tag is the user's assertion that the image fits, so its crash stays a failure.
* **Operator-owned workloads**: a workload whose controller owner is an operator's custom resource takes its image from that resource. It is named in the details and not rolled, whatever is configured, since a direct change is reverted or fought by the operator and the outcome would measure its reconcile timing; upgrade it through the custom resource. A CNF whose workloads are all operator-owned (or Jobs) is not applicable.
* **Jobs and CronJobs**: not applicable, since nothing of theirs rolls out: a Job's pod template cannot change and its pods run once, and a change to a CronJob's job template applies only to the Jobs it creates afterwards.
* **When nothing is judged**: a release with no Deployment, StatefulSet or DaemonSet is named in the details and not judged. The test is not applicable when every workload is a Job or CronJob, operator-owned, version skew, or in such a release; it is skipped when nothing has a usable previous version, or when a release's previous version could not be installed, except for Rolling downgrade, where that move is the judged step and a release that cannot be moved down fails the test.
* **Restoring images** (Rolling update, Rolling version change, Rolling downgrade): afterwards every workload the test changed is put back to its deployed image and must be ready again within the pod readiness timeout, so the next test starts from the CNF as deployed. A StatefulSet pod that never became Ready is deleted so that it is recreated from the deployed template (a forced rollback).

----------

### Containers that cannot be inspected

The tests that read a container's processes on its node, through the cluster-tools pod there, list a container they could not inspect in the details with the reason, among them: not started or not ready, with the container's state; no ready cluster-tools pod on the node; a container ID of a runtime other than containerd or CRI-O; a container that crictl does not know about, or that has no running process. A test can add reasons of its own, as Sigterm Handled's Details say. Such a container does not fail the test, and the test is skipped, naming how many containers could not be inspected and why, only when none could.

----------

### Chaos tests

CNF under network latency, CNF with host disk fill, Pod delete, Memory hog, IO Stress, Network corruption, Network duplication and Pod DNS errors each inject one [LitmusChaos](https://litmuschaos.io/) fault into the CNF's workloads, one workload at a time, and take Litmus's verdict; each test's Details names its fault. They share these rules.

* **Targets**: Litmus can target Deployments, StatefulSets and DaemonSets. A bare Pod, ReplicaSet, Job or CronJob is listed in the details and left out. A workload that owns no pod is left out too, except when it has a single selector label: that label is used without checking that the workload owns pods, and Litmus then targets whatever pods carry it, which can belong to another workload. A workload whose pod template carries no label is a finding, since Litmus selects pods by label. The test is not applicable when nothing can be targeted.
* **Selector**: a workload's pods are selected by the first of its selector labels that only its own pods carry, so a label shared by a whole Helm release does not send the fault to another workload's pod. When no label is unique to it, its first selector label is used.
* **Runs**: CNF with host disk fill and IO Stress run their experiment once per workload, into a container that can be written to. The other six run theirs once for every container of the workload: Pod delete deletes pods of the workload each time, and the other five inject into the container Litmus picks, the pod's first, each time.
* **Container runtime**: every fault except Pod delete reaches its target through the node's container runtime, which the suite detects (docker, containerd or CRI-O) from the nodes; the test is not applicable when the runtime is unsupported. CNF with host disk fill then needs the runtime's directory of containers, as its Details say. The other six need the runtime's socket: the suite probes the usual socket locations on a node, `CNTI_TESTSUITE_CONTAINER_RUNTIME_SOCKET` overrides the path, and the test is not applicable when no socket is found.
* **Verdict**: a workload passes when Litmus's verdict on each of its runs is `Pass`, and the test passes when every workload does. The Litmus 3 faults ship with their default health check off (`DEFAULT_HEALTH_CHECK` false) and the suite adds no probe, so only Pod delete checks the CNF itself, by waiting for the deleted pods to be recreated; for the other faults, `Pass` means that the experiment completed. That includes CNF with host disk fill on a container without an ephemeral-storage limit, where Litmus writes nothing, as its Details say. Every run leaves a line in the details: the verdict, the pods Litmus targeted and how long it ran, and for a failure the step that failed.
* **When Litmus does not run**: when Litmus skips an experiment (its ChaosExperiment missing, its job not created), the CNF was not tested, and the test ends as an error with Litmus's reason. So does a fault whose definition cannot be downloaded or applied. `CNTI_TESTSUITE_CHAOS_CHARTS_URL` names a mirror of the Litmus chaos charts the definitions come from. That URL must use HTTPS; a redirect it answers with is followed without checking its scheme.
* **Timeouts**: the suite waits `CNTI_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT` seconds for an experiment to finish (1800 by default), then `CNTI_TESTSUITE_GENERIC_OPERATION_TIMEOUT` seconds (60) for its verdict; a run without a `Pass` verdict by then fails.
* **Side effects**: each targeted workload is annotated `litmuschaos.io/chaos="true"`, and the annotation stays. The fault's ChaosExperiment, service account and RBAC are installed in the workload's namespace. Each ChaosEngine is deleted once its verdict is read, and a stopped run deletes it too, which ends the fault. The Litmus version is in the results file's `tools`.

----------

### Jobs and CronJobs

The tests inspect a CNF's Jobs and CronJobs as they inspect its Deployments, StatefulSets, DaemonSets, ReplicaSets and bare Pods. The configuration and security tests judge their pod templates the same way: a privileged container in a database setup Job is a finding, as it would be in a Deployment.

A Job's pods run to completion, its pod template cannot change, and it serves nothing. The tests that need a long-running workload therefore list each Job and CronJob in the test details as not applicable and judge the CNF's other workloads:

| Tests | Jobs and CronJobs |
|---|---|
| [Reasonable Startup Time](#reasonable-startup-time), [Service Discovery](#service-discovery), [Sigterm Handled](#sigterm-handled), [Liveness probe](#liveness-probe), [Readiness probe](#readiness-probe), [Prometheus installed](#prometheus-installed) | Not applicable. When the CNF has no other workload, the test is not applicable. |
| [Rollback](#rollback), [Rolling update](#rolling-update), [Rolling version change](#rolling-version-change), [Rolling downgrade](#rolling-downgrade), [Node drain](#node-drain), [OpenMetrics compatible](#openmetrics-compatible) | Not applicable. |
| The chaos tests of [Reliability, Resilience and Availability](#category-reliability-resilience-and-availability-tests) | Left out: Litmus cannot target them. |
| [Specialized Init Systems](#specialized-init-systems), [System Init Not Used](#system-init-not-used), [Routed logs](#routed-logs) | Only the pods still running are inspected. |
| [Use stdout/stderr for logs](#use-stdoutstderr-for-logs) | Finished pods are read like running ones. |
