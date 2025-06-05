# CNF TestSuite test documentation

## Table of Contents

* [**Category: Compatibility, Installability and Upgradability Tests**](#category-compatibility-installability-and-upgradability-tests)

   [[Increase decrease capacity]](#increase-decrease-capacity) | [[Helm chart published]](#helm-chart-published) | [[Helm chart valid]](#helm-chart-valid) | [[Helm deploy]](#helm-deploy) | [[Rollback]](#rollback) | [[Rolling version change]](#rolling-version-change) | [[Rolling update]](#rolling-update) | [[Rolling downgrade]](#rolling-downgrade) | [[CNI compatible]](#cni-compatible) | [[Deprecated K8s Features](#deprecated-k8s-features)]

* [**Category: Microservice Tests**](#category-microservice-tests)

   [[Reasonable Image Size]](#reasonable-image-size) | [[Reasonable Startup Time]](#reasonable-startup-time) | [[Single Process Type in One Container]](#single-process-type-in-one-container) | [[Service Discovery]](#service-discovery) | [[Shared Database]](#shared-database) | [[Specialized Init Systems]](#specialized-init-systems) | [[Sigterm Handled]](#sigterm-handled) | [[Zombie Handled]](#zombie-handled)

* [**Category: State Tests**](#category-state-tests)

   [[Node drain]](#node-drain) | [[No local volume configuration]](#no-local-volume-configuration) | [[Elastic volumes]](#elastic-volumes) | [[Database persistence]](#database-persistence)

* [**Category: Reliability, Resilience and Availability Tests**](#category-reliability-resilience-and-availability-tests)

   [[CNF under network latency]](#cnf-under-network-latency) | [[CNF with host disk fill]](#cnf-with-host-disk-fill) | [[Pod delete]](#pod-delete) | [[Memory hog]](#memory-hog) | [[IO Stress]](#io-stress) | [[Network corruption]](#network-corruption) | [[Network duplication]](#network-duplication) | [[Pod DNS errors]](#pod-dns-errors) | [[Liveness probe]](#liveness-probe) | [[Readiness probe]](#readiness-probe)

* [**Category: Observability and Diagnostic Tests**](#category-observability-and-diagnostic-tests)

   [[Use stdout/stderr for logs]](#use-stdoutstderr-for-logs) | [[Prometheus installed]](#prometheus-installed) | [[Routed logs]](#routed-logs) | [[OpenMetrics compatible]](#openmetrics-compatible) | [[Jaeger tracing]](#jaeger-tracing)

* [**Category: Security Tests**](#category-security-tests)

   [[Container socket mounts]](#container-socket-mounts) | [[Privileged Containers]](#privileged-containers) | [[External IPs]](#external-ips) | [[SELinux Options]](#selinux-options) | [[Sysctls]](#sysctls) | [[Privilege escalation]](#privilege-escalation) | [[Symlink file system]](#symlink-file-system) | [[Application credentials]](#application-credentials) | [[Host network]](#host-network) | [[Service account mapping]](#service-account-mapping) | [[Ingress and Egress blocked]](#ingress-and-egress-blocked) | [[Insecure capabilities]](#insecure-capabilities) | [[Non-root containers]](#non-root-containers) | [[Host PID/IPC privileges]](#host-pidipc-privileges) | [[Linux hardening]](#linux-hardening) | [[CPU limits]](#cpu-limits) | [[Memory limits]](#memory-limits) | [[Immutable File Systems]](#immutable-file-systems) | [[HostPath Mounts]](#hostpath-mounts)

* [**Category: Configuration Tests**](#category-configuration-tests)

   [[Default namespaces]](#default-namespaces) | [[Latest tag]](#latest-tag) | [[Require labels]](#require-labels) | [[Versioned tag]](#versioned-tag) | [[NodePort not used]](#nodeport-not-used) | [[HostPort not used]](#hostport-not-used) | [[Hardcoded IP addresses in K8s runtime configuration]](#hardcoded-ip-addresses-in-k8s-runtime-configuration) | [[Secrets used]](#secrets-used) | [[Immutable configmap]](#immutable-configmap) | [[Kubernetes Alpha APIs **PoC**]](#kubernetes-alpha-apis-poc)
* [**Category: 5G Tests**](#category-5g-tests)

   [[SMF UPF core validator]](#smf-upf-core-validator) | [[SUCI enabled]](#suci-enabled)

* [**Category: RAN Tests**](#category-ran-tests)

   [[ORAN e2 connection]](#oran-e2-connection)

* [**Category: Platform Tests**](#category-platform-tests)

   [[K8s Conformance]](#k8s-conformance) | [[ClusterAPI enabled]](#clusterapi-enabled) | [[OCI Compliant]](#oci-compliant) | [[(POC) Worker reboot recovery]](#poc-worker-reboot-recovery) | [[Cluster admin]](#cluster-admin) | [[Control plane hardening]](#control-plane-hardening) | [[Tiller images]](#tiller-images) | [[ConfigMaps encrypted]](#configmaps-encrypted) | [[Secrets encrypted]](#secrets-encrypted)

----------

## Category: Compatibility, Installability and Upgradability Tests

CNFs should work with any Certified Kubernetes product and any CNI-compatible network that meet their functionality requirements. The CNTI Test Catalog will check for usage of standard, in-band deployment tools such as Helm (version 3) charts. The CNTI Test Catalog checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s [kubectl](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources).

Service providers have historically had issues with the installability of vendor network functions. This category tests the installability and lifecycle management (the create, update, and delete of network applications) against widely used K8s installation solutions such as Helm.

### Usage

All compatibility: `./cnf-testsuite compatibility`

----------

### Increase decrease capacity

#### Overview

HPA (horizonal pod autoscale) will autoscale replicas to accommodate when there is an increase of CPU, memory or other configured metrics to prevent disruption by allowing more requests
by balancing out the utilisation across all of the pods.
Decreasing replicas works the same as increase but rather scale down the number of replicas when the traffic decreases to the number of pods that can handle the requests.
You can read more about horizonal pod autoscaling to create replicas [here](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) and in the [K8s scaling cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources).
Expectation: The number of replicas for a Pod increases and then decreases.

#### Rationale

A CNF should be able to increase and decrease its capacity without running into errors.

#### Remediation

Check out the kubectl docs for how to [manually scale your cnf.](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources)
Also here is some info about [things that could cause failures.](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#failed-deployment)

#### Usage

`./cnf-testsuite increase_decrease_capacity`

----------

### Helm chart published

#### Overview

Checks if the helm chart is found in a remote repository when running [`helm search`](https://helm.sh/docs/helm/helm_search_repo/).
Expectation: The Helm chart is published in a Helm Repsitory.

#### Rationale

If a helm chart is published, it is significantly easier to install for the end user.
The management and versioning of the helm chart are handled by the helm registry and client tools
rather than manually as directly referencing the helm chart source.

#### Remediation

Make sure your CNF helm charts are published in a Helm Repository.

#### Usage

`./cnf-testsuite helm_chart_published`

----------

### Helm chart valid

#### Overview

Checks the syntax & validity of the chart using [`helm lint`](https://helm.sh/docs/helm/helm_lint/)
Expectation: No syntax or validation problems are found in the chart.

#### Rationale

A chart should pass the [lint specification](https://helm.sh/docs/helm/helm_lint/#helm)

#### Remediation

Make sure your helm charts pass lint tests.

#### Usage

`./cnf-testsuite helm_chart_valid`

----------

### Helm deploy

#### Overview

Checks if the CNF is installed by using a Helm Chart.
Expectation: The CNF was installed using Helm.

#### Rationale

A helm chart should be [deployable to a cluster](https://helm.sh/docs/helm/helm_install/#helm)

#### Remediation

Make sure your helm charts are valid and can be deployed to clusters.

#### Usage

`./cnf-testsuite helm_deploy`

----------

### Rollback

#### Overview

Checks if the Pod can be upgraded to a new software version, then restored back to the orginal software version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) & [Kubectl Rollout Undo](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout) commands.
Expectation: The CNF Software version can be successfully incremented, then rolled back.

#### Rationale

K8s best practice is to allow [K8s to manage the rolling back](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment) of an application resource instead of having operators manually rolling back the resource by using something like blue/green deploys.

#### Remediation

Ensure that you can upgrade your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command, then rollback the upgrade using the [Kubectl Rollout Undo](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout) command.

#### Usage

`./cnf-testsuite rollback`

----------

### Rolling version change

#### Overview

Checks if the Pod can be rolled back to the original software version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) to perform a rollback.
Expectation: The CNF Software version is successfully rolled back to its original version.

#### Rationale

(update, version change, downgrade): K8s best practice for version/installation management (lifecycle management) of applications is to have [K8s track the version of the manifest information](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment) for the resource (deployment, pod, etc) internally.
Whenever a  rollback is needed the resource will have the exact manifest information that was tied to the application when it was deployed.
This adheres the principles driving immutable infrastructure and declarative specifications.

#### Remediation

Ensure that you can successfuly rollback the software version of your CNF by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnf-testsuite rolling_version_change`

----------

### Rolling update

#### Overview

Checks if the Pod can be upgraded to a new software version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-)
Expectation: The CNF Software version can be successfully incremented.

#### Rationale

See rolling version change.

#### Remediation

Ensure that you can successfuly perform a rolling upgrade of your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnf-testsuite rolling_update`

----------

### Rolling downgrade

#### Overview

Checks if the Pod can be rolled back older software version(Older than the original software version) by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) to perform a downgrade.
Expectation: The CNF Software version is successfully downgraded to a software version older than the orginal installation version.

#### Rationale

See rolling version change.

#### Remediation

Ensure that you can successfuly change the software version of your CNF back to an older version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnf-testsuite rolling_downgrade`

----------

### CNI compatible

#### Overview

This installs temporary kind clusters and will test the CNF against both Calico and Cilium CNIs.
Expectation: CNF should be compatible with multiple and different CNIs

#### Rationale

A CNF should be runnable by any CNI that adheres to the [CNI specification](https://github.com/containernetworking/cni/blob/master/SPEC.md)

#### Remediation

Ensure that your CNF is compatible with Calico, Cilium and other available CNIs.

#### Usage

`./cnf-testsuite cni_compatible`

----------

### Deprecated K8s Features

#### Overview

Checks whether any deprecated Kubernetes features (API versions, annotations, types etc.) are used by CNF. It is done
by inspecting CNF installation logs.

#### Rationale

A CNF should avoid using any deprecated features that are scheduled for removal. It should transition to stable and
actively maintained alternatives.

#### Remediation

Ensure that the CNF is not using deprecated Kubernetes features. If any are detected, follow tips from warning message displayed by testsuite and/or consult [Deprecated API Migration Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/).

#### Usage

`./cnf-testsuite deprecated_k8s_features`

----------

## Category: Microservice Tests

The CNF should be developed and delivered as a microservice. The CNTI Test Catalog tests to determine the organizational structure and rate of change of the CNF being tested. Once these are known we can detemine whether or not the CNF is a microservice. See: [Microservice-Principles](https://networking.cloud-native-principles.org/cloud-native-microservice-principles)

[Good microservice practices](https://vmblog.com/archive/2022/01/04/the-zeitgeist-of-cloud-native-microservices.aspx) promote agility which means less time will occur between deployments.  One benefit of more agility is it allows for different organizations and teams to deploy at the rate of change that they build out features, instead of deploying in lock step with other teams. This is very important when it comes to changes that are time sensitive like security patches.

### Usage

All microservice: `./cnf-testsuite microservice`

----------

### Reasonable Image Size

#### Overview

Checks the size of the image used.
Expectation: Each CNF image size is under 500 MB.

#### Rationale

A CNF with smaller image sizes provides faster deployment and scaling (critical for functions like 5G control plane components), enables faster updates, reduces the risk of timeouts, and reduces the attack surface (key for regulated telecom environments).  In addition, smaller image sizes are important in edge/disaggregated deployments common in Open RAN and MEC scenarios.

#### Remediation

Audit your CNF's images:

1. Identify and remove unused libraries, tools, and test artifacts.
2. Seperate build-time from run-time dependancies.
3. Prefer distroless, alpine, or slim OS images.
4. Modularize large CNFs into seperate containers or microservices.

#### Usage

`./cnf-testsuite reasonable_image_size`

----------

### Reasonable Startup Time

#### Overview

Checks how long it takes for the CNF to pass a Readiness Probe and reach a ready/running state.
Expectation: CNF starts up under one minute

#### Rationale

A CNF that starts up with a time (adjusted for server resources) that is approaching a minute is indicative of a monolithic application. The liveness probe's `initialDelaySeconds` and `failureThreshold` determine the startup time and retry amount of the CNF. Specifically, if the `initialDelay` is too long, it is indicative of a monolithic application. If the `failureThreshold` is too high, it is indicative of a CNF or a component of the CNF that has too many intermittent failures.

#### Remediation

Ensure that your CNF gets into a running state within 30 seconds.

#### Usage

`./cnf-testsuite reasonable_startup_time`

----------

### Single Process Type in One Container

#### Overview

This verifies that there is only one process type within one container. This does not count against child processes. For example, nginx or httpd could have a parent process and then 10 child processes, but if both nginx and httpd were running, this test would fail.
Expectation: CNF container has one process type

#### Rationale

A microservice should have only one process (or set of parent/child processes) that is managed by a non-homegrown supervisor or orchestrator. The microservice should not spawn other process types (e.g., executables) as a way to contribute to the workload but rather should interact with other processes through a microservice API.

#### Remediation

Ensure that there is only one process type within a container. This does not count against child processes, e.g., nginx or httpd could be a parent process with 10 child processes and pass this test, but if both nginx and httpd were running, this test would fail.

#### Usage

`./cnf-testsuite single_process_type`

----------

### Service Discovery

#### Overview

This tests and checks if the containers within a CNF have services exposed via a Kubernetes Service resource. Application access for microservices within a cluster should be exposed via a Service. Read more about K8s Service [here](https://kubernetes.io/docs/concepts/services-networking/service/).
Expectation: CNFs accessible to other applications should be exposed via a Service.

#### Rationale

A K8s microservice should expose its API through a K8s service resource. K8s services handle service discovery and load balancing for the cluster, ensuring that microservices can efficiently communicate and distribute traffic among themselves.

#### Remediation

Make sure the CNF exposes any of its containers as a Kubernetes Service. This is crucial for enabling service discovery and load balancing within the cluster, facilitating smoother operation and communication between microservices. You can learn more about Kubernetes Service [here](https://kubernetes.io/docs/concepts/services-networking/service/).

#### Usage

`./cnf-testsuite service_discovery`

----------

### Shared Database

#### Overview

This tests if multiple CNFs are using the same database.
Expectation: Multiple microservices should not share the same database.

#### Rationale

A K8s microservice should not share a database with another K8s database because it forces the two services to upgrade in lock step.

#### Remediation

Make sure that your CNFs containers are not sharing the same [database](https://martinfowler.com/bliki/IntegrationDatabase.html).

#### Usage

`./cnf-testsuite shared_database`

----------

### Specialized Init Systems

#### Overview

This tests if containers in pods have dumb-init, tini or s6-overlay as init processes.
Expectation: Container images should use specialized init systems for containers.

#### Rationale

There are proper init systems and sophisticated supervisors that can be run inside of a container. Both of these systems properly reap and pass signals. Sophisticated supervisors are considered overkill because they take up too many resources and are sometimes too complicated. Some examples of sophisticated supervisors are: supervisord, monit, and runit. Proper init systems are smaller than sophisticated supervisors and therefore suitable for containers. Some of the proper container init systems are tini, dumb-init, and s6-overlay.

#### Remediation

Use init systems that are purpose-built for containers like tini, dumb-init, s6-overlay.

#### Usage

`./cnf-testsuite specialized_init_system`

----------

### Sigterm Handled

#### Overview

This tests if the PID 1 process of containers handles SIGTERM.
Expectation: Sigterm is handled by PID 1 process of containers.

#### Rationale

The Linux kernel handles signals differently for the process that has PID 1 than it does for other processes. Signal handlers aren't automatically registered for this process, meaning that signals such as SIGTERM or SIGINT will have no effect by default. By default, one must kill processes by using SIGKILL, preventing any graceful shutdown. Depending on the application, using SIGKILL can result in user-facing errors, interrupted writes (for data stores), or unwanted alerts in a monitoring system.

#### Remediation

Make the PID 1 container process to handle SIGTERM; enable process namespace sharing in Kubernetes or use specialized Init system.

#### Usage

`./cnf-testsuite sig_term_handled`

----------

### Zombie Handled

#### Overview

This tests if the PID 1 process of containers handles/reaps zombie processes.
Expectation: Zombie processes are handled/reaped by PID 1 process of containers.

#### Rationale

Classic init systems such as systemd are also used to remove (reap) orphaned, zombie processes. Orphaned processes — processes whose parents have died - are reattached to the process that has PID 1, which should reap them when they die. A normal init system does that. But in a container, this responsibility falls on whatever process has PID 1. If that process doesn't properly handle the reaping, you risk running out of memory or some other resources.

#### Remediation

Make the PID 1 container process to handle/reap zombie processes; enable process namespace sharing in Kubernetes or use specialized Init system.

#### Usage

`./cnf-testsuite zombie_handled`

----------

## Category: State Tests

The CNTI Test Catalog checks if state is stored in a [custom resource definition](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) or a separate database (e.g. [etcd](https://github.com/etcd-io/etcd)) rather than requiring local storage. It also checks to see if state is resilient to node failure

If infrastructure is immutable, it is easily reproduced, consistent, disposable, will have a repeatable deployment process, and will not have configuration or artifacts that are modifiable in place.
This ensures that all *configuration* is stateless.
Any [*data* that is persistent](https://vmblog.com/archive/2022/05/16/stateful-cnfs.aspx) should be managed by K8s statefulsets.

### Usage

All state: `./cnf-testsuite state`

----------

### Node drain

#### Overview

A node is drained and workload resources rescheduled to another node, passing with a liveness and readiness check. This will skip when the cluster only has a single node.
Expectation: All workload resources are successfully rescheduled onto other available node(s).

#### Rationale

No CNF should fail because of stateful configuration. A CNF should function properly if it is rescheduled on other nodes.
This test will remove resources which are running on a target node and reschedule them on the another node.

#### Remediation

Ensure that your CNF can be successfully rescheduled when a node fails or is [drained](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)

#### Usage

`./cnf-testsuite node_drain`

----------

### No local volume configuration

#### Overview

This tests if local volumes are being used for the CNF.
Expectation: Local storage should not be used or configured.

#### Rationale

A CNF should refrain from using the [local storage class](https://kubernetes.io/docs/concepts/storage/storage-classes/#local)

#### Remediation

Ensure that your CNF isn't using any persistent volumes that use a ["local"] mount point.

#### Usage

`./cnf-testsuite no_local_volume_configuration`

----------

### Elastic volumes

#### Overview

This checks for elastic persistent volumes in use by the CNF.
Expectation: Elastic persistent volumes should be configured for statefulness.

#### Rationale

A cnf that uses elastic volumes can be rescheduled to other nodes by the orchestrator easily

#### Remediation

Setup and use elastic persistent volumes instead of local storage.

#### Usage

`./cnf-testsuite elastic_volume`

----------

### Database persistence

#### Overview

This checks if elastic volumes and stateful sets are used for MySQL databases. If no MySQL database is found, the test is skipped.
Expectation: Elastic volumes and or statefulsets should be used for databases to maintain a minimum resilience level in K8s clusters.

#### Rationale

When a traditional database such as mysql is configured to use statefulsets, it allows the database to use a persistent identifier that it maintains across any rescheduling.
Persistent Pod identifiers make it easier to match existing volumes to the new Pods that have been rescheduled.
<https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/>

#### Remediation

Select a database configuration that uses statefulsets and elastic storage volumes.

#### Usage

`./cnf-testsuite database_persistence`

----------

## Category: Reliability, Resilience and Availability Tests

[Cloud Native Definition](https://github.com/cncf/toc/blob/master/DEFINITION.md) requires systems to be Resilient to failures inevitable in cloud environments. CNF Resilience should be tested to ensure CNFs are designed to deal with non-carrier-grade shared cloud HW/SW platform

Cloud native systems promote resilience by putting a high priority on testing individual components (chaos testing) as they are running (possibly in production).
[Reliability in traditional telecommunications](https://vmblog.com/archive/2021/09/15/cloud-native-chaos-and-telcos-enforcing-reliability-and-availability-for-telcos.aspx) is handled differently than in Cloud Native systems. Cloud native systems try to address reliability (MTBF) by having the subcomponents have higher availability through higher serviceability (MTTR) and redundancy. For example, having ten redundant subcomponents where seven components are available and three have failed will produce a top level component that is more reliable (MTBF) than a single component that "never fails" in the cloud native world.

### Usage

All resilience: `./cnf-testsuite resilience`

----------

### CNF under network latency

#### Overview

[This experiment](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-latency/) causes network degradation without the pod being marked unhealthy/unworthy of traffic by kube-proxy (unless you have a liveness probe of sorts that measures latency and restarts/crashes the container). The idea of this experiment is to simulate issues within your pod network OR microservice communication across services in different availability zones/regions etc.
The applications may stall or get corrupted while they wait endlessly for a packet. The experiment limits the impact (blast radius) to only the traffic you want to test by specifying IP addresses or application information. This experiment will help to improve the resilience of your services over time.
Expectation: The CNF should continue to function when network latency occurs

#### Rationale

Network latency can have a significant impact on the overall performance of the application.  Network outages that result from low latency can cause
a range of failures for applications and can severely impact user/customers with downtime. This chaos experiment allows you to see the impact of latency
traffic on the CNF.

#### Remediation

Ensure that your CNF doesn't stall or get into a corrupted state when network degradation occurs.
A mitigation stagagy (in this case keep the timeout i.e., access latency low) could be via some middleware that can switch traffic based on some SLOs parameters.

#### Usage

`./cnf-testsuite pod_network_latency`

----------

### CNF with host disk fill

#### Overview

[This experiment](https://litmuschaos.github.io/litmus/experiments/categories/pods/disk-fill/) stresses the disk with continuous and heavy IO to cause degradation in the shared disk. This experiment also reduces the amount of scratch space available on a node which can lead to a lack of space for newer containers to get scheduled. This can cause (Kubernetes gives up by applying an "eviction" taint like "disk-pressure") a wholesale movement of all pods to other nodes.
Expectation: The CNF should continue to function when disk fill occurs and pods should not be evicted to another node.

#### Rationale

Disk Pressure is a scenario we find in Kubernetes applications that can result in the eviction of the application replica and impact its delivery. Such scenarios can still occur despite whatever availability aids K8s provides. These problems are generally referred to as "Noisy Neighbour" problems.

#### Remediation

Ensure that your CNF is resilient and doesn't stall when heavy IO causes a degradation in storage resource availability.

#### Usage

`./cnf-testsuite disk_fill`

----------

### Pod delete

#### Overview

[This experiment](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-delete/) helps to simulate such a scenario with forced/graceful pod failure on specific or random replicas of an application resource and checks the deployment sanity (replica availability & uninterrupted service) and recovery workflow of the application.
Expectation: The CNF should continue to function when pod delete occurs

#### Rationale

In a distributed system like Kubernetes, application replicas may not be sufficient to manage the traffic (indicated by SLIs) when some replicas are unavailable due to any failure (can be system or application). The application needs to meet the SLO (service level objectives) for this. It's imperative that the application has defenses against this sort of failure to ensure that the application always has a minimum number of available replicas.

#### Remediation

Ensure that your CNF is resilient and doesn't fail on a forced/graceful pod failure on specific or random replicas of an application.

#### Usage

`./cnf-testsuite pod_delete`

----------

### Memory hog

#### Overview

The [pod-memory hog](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-memory-hog/) experiment launches a stress process within the target container - which can cause either the primary process in the container to be resource constrained in cases where the limits are enforced OR eat up available system memory on the node in cases where the limits are not specified.
Expectation: The CNF should continue to function when pod memory hog occurs

#### Rationale

If the memory policies for a CNF are not set and granular, containers on the node can be killed based on their oom_score and the QoS class a given pod belongs to (best-effort ones are first to be targeted). This eval is extended to all pods running on the node, thereby causing a bigger blast radius.

#### Remediation

Ensure that your CNF is resilient to heavy memory usage and can maintain some level of availability.

#### Usage

`./cnf-testsuite pod_memory_hog`

----------

### IO Stress

#### Overview

The [pod-io stress](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-io-stress/) experiment the disk with continuous and heavy IO to cause degradation in reads/writes by other microservices that use this shared disk.
Expectation: The CNF should continue to function when pod io stress occurs

#### Rationale

Stressing the disk with continuous and heavy IO can cause degradation in reads/ writes by other microservices that use this
shared disk.  Scratch space can be used up on a node which leads to the lack of space for newer containers to get scheduled which
causes a movement of all pods to other nodes. This test determines the limits of how a CNF uses its storage device.

#### Remediation

Ensure that your CNF is resilient to continuous and heavy disk IO load and can maintain some level of availability

#### Usage

`./cnf-testsuite pod_io_stress`

----------

### Network corruption

#### Overview

The [pod-network corruption](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-corruption/) experiment injects packet corruption on the CNF by starting a traffic control (tc) process with netem rules to add egress packet corruption.
Expectation: The CNF should be resilient to a lossy/flaky network and should continue to provide some level of availability.

#### Rationale

A higher quality CNF should be resilient to a lossy/flaky network.  This test injects packet corruption on the specified CNF's container by
starting a traffic control (tc) process with netem rules to add egress packet corruption.

#### Remediation

Ensure that your CNF is resilient to a lossy/flaky network and can maintain a level of availability.

#### Usage

`./cnf-testsuite pod_network_corruption`

----------

### Network duplication

#### Overview

The [pod-network duplication](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-duplication/) experiment injects network duplication into the CNF by starting a traffic control (tc) process with netem rules to add egress delays.
Expectation: The CNF should continue to function and be resilient to a duplicate network.

#### Rationale

A higher quality CNF should be resilient to erroneously duplicated packets. This test injects network duplication on the specified container
by starting a traffic control (tc) process with netem rules to add egress delays.

#### Remediation

Ensure that your CNF is resilient to erroneously duplicated packets and can maintain a level of availability.

#### Usage

`./cnf-testsuite pod_network_duplication`

----------

### Pod DNS errors

#### Overview

The [pod-dns error](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-dns-error/) experiment injects chaos to disrupt DNS resolution in kubernetes pods and causes loss of access to services by blocking DNS resolution of hostnames/domains.
Expectation: That the CNF dosen't crash is resilient to DNS resolution failures.

#### Rationale

A CNF should be resilient to name resolution (DNS) disruptions within the kubernetes pod. This ensures that at least some application availability will be maintained if DNS resolution fails.

#### Remediation

Ensure that your CNF is resilient to DNS resolution failures can maintain a level of availability.

#### Usage

`./cnf-testsuite pod_dns_error`

----------

### Liveness probe

#### Overview

This test verifies that each workload resource includes at least one container with a liveness probe configured.
Expectation: Each workload resource should have at least one container with a liveness probe defined.

#### Rationale

A cloud native principle is that application developers understand their own resilience requirements better than operators:

> "No one knows more about what an application needs to run in a healthy state than the developer. For a long time, infrastructure administrators have tried to figure out what “healthy” means for applications they are responsible for running. Without knowledge of what actually makes an application healthy, their attempts to monitor and alert when applications are unhealthy are often fragile and incomplete. To increase the operability of cloud native applications, applications should expose a health check." -- Garrison, Justin; Nova, Kris. Cloud Native Infrastructure: Patterns for Scalable Infrastructure and Applications in a Dynamic Environment. O'Reilly Media. Kindle Edition.

This is exemplified in the Kubernetes best practice of pods declaring how they should be managed through the liveness and readiness entries in the pod's configuration.

#### Remediation

Ensure that your CNF has a [Liveness Probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) configured.

#### Usage

`./cnf-testsuite liveness`

----------

### Readiness probe

#### Overview

This test verifies that each workload resource includes at least one container with a readiness probe configured.
Expectation: Each workload resource should have at least one container with a readiness probe defined.

#### Rationale

A CNF should tell Kubernetes when it is [ready to serve traffic](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-readiness-probes).

#### Remediation

Ensure that your CNF has a [Readiness Probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) configured.

#### Usage

`./cnf-testsuite readiness`

----------

## Category: Observability and Diagnostic Tests

In order to maintain, debug, and have insight into a protected environment, infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends itself to metrics, tracing, and logging.

In order to maintain, debug, and have insight into a production environment that is protected (versioned, kept in source control, and changed only by using a deployment pipeline), its infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends itself to metrics, tracing, and logging.

### Usage

All observability: `./cnf-testsuite observability`

----------

### Use stdout/stderr for logs

#### Overview

This checks and verifies that STDOUT/STDERR logging is configured for the CNF.
Expectation: Resource output logs should be sent to STDOUT/STDERR

#### Rationale

By sending logs to standard out/standard error [logs will be treated like event streams](https://12factor.net/) as recommended by 12 factor apps principles.

#### Remediation

Make sure applications and CNF's are sending log output to STDOUT and or STDERR.

#### Usage

`./cnf-testsuite log_output`

----------

### Prometheus installed

#### Overview

Tests for the presence of [Prometheus](https://prometheus.io/) and if the CNF configured to sent metrics to the prometheus server.
Expectation: The CNF is configured and sending metrics to a Prometheus server.

#### Rationale

Recording metrics within a cloud native deployment is important because it gives the maintainer of a cluster of hundreds or thousands of services the ability to pinpoint [small anomalies](https://about.gitlab.com/blog/2018/09/27/why-all-organizations-need-prometheus/), such as those that will eventually cause a failure.

#### Remediation

Install and configure Prometheus for your CNF.

#### Usage

`./cnf-testsuite prometheus_traffic`

----------

### Routed logs

#### Overview

Checks for presence of a Unified Logging Layer and if the CNFs logs are being captured by the Unified Logging Layer. fluentd and fluentbit are currently supported.
Expectation: Fluentd or FluentBit is installed and capturing logs for the CNF.

#### Rationale

A CNF should have logs managed by a [unified logging layer](https://www.fluentd.org/why) It's considered a best-practice for CNFs to route logs and data through programs like fluentd to analyze and better understand data.

#### Remediation

Install and configure fluentd or fluentbit to collect data and logs. See more at [fluentd.org](https://bit.ly/fluentd) for fluentd or [fluentbit.io](https://fluentbit.io/) for fluentbit.

#### Usage

`./cnf-testsuite routed_logs`

----------

### OpenMetrics compatible

#### Overview

Checks if the CNFs metrics are [OpenMetrics](https://openmetrics.io/) compliant.
Expectation: CNF should emit OpenMetrics compatible traffic.

#### Rationale

OpenMetrics is the de facto standard for transmitting cloud native metrics at scale, with support for both text representation and Protocol Buffers and brings it into an Internet Engineering Task Force (IETF) standard. A CNF should expose metrics that are [OpenMetrics compatible](https://github.com/OpenObservability/OpenMetrics/blob/main/specification/OpenMetrics.md)

#### Remediation

Ensure that your CNF is publishing OpenMetrics compatible metrics.

#### Usage

`./cnf-testsuite open_metrics`

----------

### Jaeger tracing

#### Overview

Checks if Jaeger is installed and the CNF is configured to send traces to the Jaeger Server.
Expectation: The CNF is sending traces to Jaeger.

#### Rationale

A CNF should provide tracing that conforms to the [open telemetry tracing specification](https://opentelemetry.io/docs/reference/specification/trace/api/)

#### Remediation

Ensure that your CNF is both using & publishing traces to Jaeger.

#### Usage

`./cnf-testsuite tracing`

----------

## Category: Security Tests

CNF containers should be isolated from one another and the host. The CNTI Test Catalog uses tools like [OPA Gatekeeper](https://github.com/open-policy-agent/gatekeeper) and [Armosec Kubescape](https://github.com/armosec/kubescape)

> "Cloud native security is a [...] mutifaceted topic [...] with multiple, diverse components that need to be secured. The cloud platform, the underlying host operating system, the container runtime, the container orchestrator,and then the applications themselves each require specialist security attention" -- Chris Binne, Rory Mccune. Cloud Native Security. (Wiley, 2021)(pp. xix)

### Usage

All security: `./cnf-testsuite security`

----------

### Container socket mounts

#### Overview

This test checks all of the CNFs containers and looks to see if any of them have access a container runtime socket from the host.
Expectation: Container runtime sockets should not be mounted as volumes

#### Rationale

[Container daemon socket bind mounts](https://kyverno.io/policies/best-practices/disallow_cri_sock_mount/disallow_cri_sock_mount/) allows access to the container engine on the node. This access can be used for privilege escalation and to manage containers outside of Kubernetes, and hence should not be allowed.

#### Remediation

Make sure your CNF doesn't mount `/var/run/docker.sock`, `/var/run/containerd.sock` or `/var/run/crio.sock` on any containers.

#### Usage

`./cnf-testsuite container_sock_mounts`

----------

### Privileged Containers

#### Overview

Checks if any containers are running in privileged mode.
Expectation: Containers should not run in privileged mode

#### Rationale

> "... docs describe Privileged mode as essentially enabling “…access to all devices on the host as well as [having the ability to] set some configuration in AppArmor or SElinux to allow the container nearly all the same access to the host as processes running outside containers on the host.” In other words, you should rarely, if ever, use this switch on your container command line." -- Binnie, Chris; McCune, Rory (2021-06-17T23:58:59). Cloud Native Security . Wiley. Kindle Edition.

#### Remediation

Remove privileged capabilities by setting the securityContext.privileged to false. If you must deploy a Pod as privileged, add other restriction to it, such as network policy, Seccomp etc and still remove all unnecessary capabilities.

#### Usage

`./cnf-testsuite privileged_containers`

----------

### External IPs

#### Overview

Checks if the CNF has services with external IPs configured
Expectation: A CNF should not run services with external IPs

#### Rationale

Service external IPs can be used for a MITM attack (CVE-2020-8554). Restrict external IPs or limit to a known set of addresses.
See: <https://github.com/kyverno/kyverno/issues/1367>

#### Remediation

Make sure to not define external IPs in your kubernetes service configuration

#### Usage

`./cnf-testsuite external_ips`

----------

### SELinux Options

#### Overview

Checks if the CNF has escalatory SELinuxOptions configured.
Expectation: A CNF should not have any 'seLinuxOptions' configured that allow privilege escalation.

#### Rationale

If [SELinux options](https://kyverno.io/policies/pod-security/baseline/disallow-selinux/disallow-selinux/) is configured improperly it can be used to escalate privileges and should not be allowed.

#### Remediation

Ensure the following guidelines are followed for any cluster resource that allow SELinux options:

* If the SELinux option `type` is set, it should only be one of the allowed values: `container_t`, `container_init_t`, or `container_kvm_t`.
* SELinux options `user` or `role` should not be set.

#### Usage

`./cnf-testsuite selinux_options`

----------

### Sysctls

#### Overview

Checks the CNF for usage of non-namespaced sysctls mechanisms that can affect the entire host.
Expectation: The CNF should only have "safe" sysctls mechanisms configured, that are isolated from other Pods.

#### Rationale

Sysctls can disable security mechanisms or affect all containers on a host, and should be disallowed except for an allowed "safe" subset. A sysctl is considered safe if it is namespaced in the container or the Pod, and it is isolated from other Pods or processes on the same Node. This test ensures that only those "safe" subsets are specified in a Pod.

#### Remediation

The spec.securityContext.sysctls field must be unset or not use.

#### Usage

`./cnf-testsuite sysctls`

----------

### Privilege escalation

#### Overview

Check that the allowPrivilegeEscalation field in the securityContext of each container is set to false.
Expectation: Containers should not allow privilege escalation

#### Rationale

*When [privilege escalation](https://kubernetes.io/docs/concepts/policy/pod-security-policy/#privilege-escalation) is [enabled for a container](https://hub.armo.cloud/docs/c-0016), it will allow setuid binaries to change the effective user ID, allowing processes to turn on extra capabilities.
In order to prevent illegitimate escalation by processes and restrict a processes to a NonRoot user mode, escalation must be disabled.

#### Remediation

If your application does not need it, make sure the allowPrivilegeEscalation field of the securityContext is set to false. See more at [ARMO-C0016](https://bit.ly/C0016_privilege_escalation)

#### Usage

`./cnf-testsuite privilege_escalation`

----------

### Symlink file system

#### Overview

This test checks for vulnerable K8s versions and the actual usage of the subPath feature for all Pods in the CNF.
Expectation: No vulnerable K8s version being used in conjunction with the subPath feature.

#### Rationale

Due to CVE-2021-25741, subPath or subPathExpr volume mounts can be [used to gain unauthorised access](https://hub.armo.cloud/docs/c-0058) to files and directories anywhere on the host filesystem. In order to follow a best-practice security standard and prevent unauthorised data access, there should be no active CVEs affecting either the container or underlying platform.

#### Remediation

To mitigate this vulnerability without upgrading kubelet, you can disable the VolumeSubpath feature gate on kubelet and kube-apiserver, or remove any existing Pods using subPath or subPathExpr feature.

#### Usage

`./cnf-testsuite symlink_file_system`

----------

### Application credentials

#### Overview

Checks the CNF for sensitive information in environment variables, by using list of known sensitive key names. Also checks for configmaps with sensitive information.
Exepectation: Application credentials should not be found in the CNFs configuration files

#### Rationale

Developers store secrets in the Kubernetes configuration files, such as environment variables in the pod configuration. Such behavior is commonly seen in clusters that are monitored by Azure Security Center.
Attackers who have access to those configurations, by querying the API server or by accessing those files on the developer’s endpoint, can steal the stored secrets and use them.

#### Remediation

Use Kubernetes secrets or Key Management Systems to store credentials.

#### Usage

`./cnf-testsuite application_credentials`

----------

### Host network

#### Overview

Checks if there is a [host network](https://bit.ly/C0041_hostNetwork) attached to any of the Pods in the CNF.
Expectation: The CNF should not have access to the host systems network.

#### Rationale

When a container has the [hostNetwork](https://hub.armo.cloud/docs/c-0041) feature turned on, the container has direct access to the underlying hostNetwork. Hackers frequently exploit this feature to [facilitate a container breakout](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/1/CTR_KUBERNETES%20HARDENING%20GUIDANCE.PDF) and gain access to the underlying host network, data and other integral resources.

#### Remediation

Only connect PODs to the hostNetwork when it is necessary. If not, set the hostNetwork field of the pod spec to false, or completely remove it (false is the default). Allow only those PODs that must have access to host network by design.

#### Usage

`./cnf-testsuite host_network`

----------

### Service account mapping

#### Overview

heck if the CNF is using service accounts that are automatically mapped.
Expectation: The [automatic mapping](https://bit.ly/C0034_service_account_mapping) of service account tokens should be disabled.

#### Rationale

When a pod gets created and a service account wasn't specified, then the default service account will be used. Service accounts assigned in this way can unintentionally give third-party applications root access to the K8s APIs and other applicaton services. In order to follow a zero-trust / fine-grained security methodology, this functionality will need to be explicitly disabled by using the automountServiceAccountToken: false flag. In addition, if RBAC is not enabled, the SA has unlimited permissions in the cluster.

#### Remediation

Disable automatic mounting of service account tokens to PODs either at the service account level or at the individual POD level, by specifying the automountServiceAccountToken: false. Note that POD level takes precedence.

#### Usage

`./cnf-testsuite service_account_mapping`

----------

### Ingress and Egress blocked

#### Overview

Checks each Pod in the CNF for a defined ingress and egress policy.
Expectation: Ingress and Egress traffic should be blocked on Pods.

#### Rationale

By default, [no network policies are applied](https://hub.armo.cloud/docs/c-0030) to Pods or namespaces, resulting in unrestricted ingress and egress traffic within the Pod network. In order to [prevent lateral movement](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/1/CTR_KUBERNETES%20HARDENING%20GUIDANCE.PDF) or escalation on a compromised cluster, administrators should implement a default policy to deny all ingress and egress traffic.
This will ensure that all Pods are isolated by default and further policies could then be used to specifically relax these restrictions on a case-by-case basis.

#### Remediation

By default, you should disable or restrict Ingress and Egress traffic on all pods.

#### Usage

`./cnf-testsuite ingress_egress_blocked`

----------

### Insecure capabilities

#### Overview

Checks the CNF for any usage of insecure capabilities using the following [deny list](https://man7.org/linux/man-pages/man7/capabilities.7.html)
Expectation: Containers should not have insecure capabilities enabled.

#### Rationale

Giving [insecure](https://hub.armo.cloud/docs/c-0046) and unnecessary capabilities for a container can increase the impact of a container compromise.

#### Remediation

Remove all insecure capabilities which aren’t necessary for the container.

#### Usage

`./cnf-testsuite insecure_capabilities`

----------

### Non-root containers

#### Overview

Checks if the CNF has runAsUser and runAsGroup set to a user id greater than 999. Also checks that the allowPrivilegeEscalation field is set to false for the CNF.
Read more at [ARMO-C0013](https://bit.ly/2Zzlts3)
Expectation: Containers should run with non-root user and allowPrivilegeEscalation should be set to false.

#### Rationale

Container engines allow containers to run applications as a non-root user with non-root group membership. Typically, this non-default setting is configured when the container image is built. . Alternatively, Kubernetes can load containers into a Pod with SecurityContext:runAsUser specifying a non-zero user. While the runAsUser directive effectively forces non-root execution at deployment, [NSA and CISA encourage developers](https://hub.armo.cloud/docs/c-0013) to build container applications to execute as a non-root user. Having non-root execution integrated at build time provides better assurance that applications will function correctly without root privileges.

#### Remediation

If your application does not need root privileges, make sure to define the runAsUser and runAsGroup under the PodSecurityContext to use user ID 1000 or higher, do not turn on allowPrivlegeEscalation bit and runAsNonRoot is true.

#### Usage

`./cnf-testsuite non_root_containers`

----------

### Host PID/IPC privileges

#### Overview

Checks if containers are running with hostPID or hostIPC privileges.
Read more at [ARMO-C0038](https://bit.ly/3nGvpIQ)
Expectation: Containers should not have hostPID and hostIPC privileges

#### Rationale

Containers should be isolated from the host machine as much as possible. The [hostPID and hostIPC](https://hub.armo.cloud/docs/c-0038) fields in deployment yaml may allow cross-container influence and may expose the host itself to potentially malicious or destructive actions. This control identifies all PODs using hostPID or hostIPC privileges.

#### Remediation

Apply least privilege principle and remove hostPID and hostIPC from the yaml configuration privileges unless they are absolutely necessary.

#### Usage

`./cnf-testsuite host_pid_ipc_privileges`

----------

### Linux hardening

#### Overview

Check if there are AppArmor, Seccomp, SELinux or Capabilities defined in the securityContext of the CNF's containers and pods.
Read more at [ARMO-C0055](https://bit.ly/2ZKOjpJ).
Expectation: Security services are being used to harden application.

#### Rationale

In order to reduce the attack surface, it is recommend, when it is possible, to harden your application using [security services](https://hub.armo.cloud/docs/c-0055) such as SELinux®, AppArmor®, and seccomp. Starting from Kubernetes version 1.22, SELinux is enabled by default.

#### Remediation

Use AppArmor, Seccomp, SELinux and Linux Capabilities mechanisms to restrict containers abilities to utilize unwanted privileges.

#### Usage

`./cnf-testsuite linux_hardening`

----------

### CPU limits

#### Overview

Check if there is a ‘containers[].resources.limits.cpu’ field defined for all pods in the CNF.
Expectation: Containers should have cpu limits defined

#### Rationale

Every container [should have a limit set for the CPU available for it](https://hub.armo.cloud/docs/c-0270) set for every container or a namespace to prevent resource exhaustion. This test identifies all the Pods without CPU limit definitions by checking their yaml definition file as well as their namespace LimitRange objects. It is also recommended to use ResourceQuota object to restrict overall namespace resources, but this is not verified by this test.

#### Remediation

Define LimitRange and ResourceQuota policies to limit CPU usage for namespaces or in the deployment/POD yamls.

#### Usage

`./cnf-testsuite cpu_limits`

----------

### Memory limits

#### Overview

Check if there is a ‘containers[].resources.limits.memory’ field defined for all pods in the CNF.
Expectation: Containers should have memory limits defined

#### Rationale

Every container [should have a limit set for the memory available for it](https://hub.armo.cloud/docs/c-0271) set for every container or a namespace to prevent resource exhaustion. This test identifies all the Pods without memory limit definitions by checking their yaml definition file as well as their namespace LimitRange objects. It is also recommended to use ResourceQuota object to restrict overall namespace resources, but this is not verified by this test.

#### Remediation

Define LimitRange and ResourceQuota policies to limit memory usage for namespaces or in the deployment/POD yamls.

#### Usage

`./cnf-testsuite memory_limits`

----------

### Immutable File Systems

#### Overview

Checks whether the readOnlyRootFilesystem field in the SecurityContext is set to true.
Read more at [ARMO-C0017](https://bit.ly/3pSMtxK)
Expectation: Containers should use an immutable file system when possible.

#### Rationale

Mutable container filesystem can be abused to gain malicious code and data injection into containers. By default, containers are permitted unrestricted execution within their own context.
An attacker who has access to a container, [can create files](https://hub.armo.cloud/docs/c-0017) and download scripts as they wish, and modify the underlying application running on the container.

#### Remediation

Set the filesystem of the container to read-only when possible. If the containers application needs to write into the filesystem, it is possible to mount secondary filesystems for specific directories where application require write access.

#### Usage

`./cnf-testsuite immutable_file_systems`

----------

### HostPath Mounts

#### Overview

Checks the CNF's POD spec for any hostPath volumes, if found it checks the volume for the field mount.readOnly == false (or if it doesn’t exist).
Read more at [ARMO-C0045](https://bit.ly/3EvltIL)
Expectation: Containers should not have hostPath mounts

#### Rationale

[hostPath mount](https://hub.armo.cloud/docs/c-0006) can be used by attackers to get access to the underlying host and thus break from the container to the host. (See “3: Writable hostPath mount” for details).

#### Remediation

Refrain from using a hostPath mount.

#### Usage

`./cnf-testsuite hostpath_mounts`

----------

## Category: Configuration Tests

Configuration should be managed in a declarative manner, using [ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/), [Operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/), or other [declarative interfaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/#understanding-kubernetes-objects).

Declarative APIs for an immutable infrastructure are anything that configures the infrastructure element. This declaration can come in the form of a YAML file or a script, as long as the configuration designates the desired outcome, not how to achieve said outcome.

> "Because it describes the state of the world, declarative configuration does not have to be executed to be understood. Its impact is concretely declared. Since the effects of declarative configuration can be understood before they are executed, declarative configuration is far less error-prone." -- Hightower, Kelsey; Burns, Brendan; Beda, Joe. Kubernetes: Up and Running: Dive into the Future of Infrastructure (Kindle Locations 183-186). Kindle Edition*

### Usage

All configuration: `./cnf-testsuite configuration_lifecycle`

----------

### Default namespaces

#### Overview

Checks if any of the CNF's resources are deployed in the default namespace.
Expectation: Resources should not be deployed in the default namespace.

#### Rationale

Namespaces provide a way to segment and isolate cluster resources across multiple applications and users.
As a best practice, workloads should be isolated with Namespaces and not use the default namespace.

#### Remediation

Ensure that your CNF is configured to use a Namespace and is not using the default namespace.

#### Usage

`./cnf-testsuite default_namespace`

----------

### Latest tag

#### Overview

Checks if the CNF is using a 'latest' tag instead of a semantic version.
Expectation: The CNF should use an immutable tag that maps to a symantic version of the application.

#### Rationale

You should [avoid using the :latest tag](https://kubernetes.io/docs/concepts/containers/images/) when deploying containers in production as it is harder to track which version of the image is running and more difficult to roll back properly.

#### Remediation

When specifying container images, always specify a tag and ensure to use an immutable tag that maps to a specific version of an application Pod. Remove any usage of the `latest` tag, as it is not guaranteed to be always point to the same version of the image.

#### Usage

`./cnf-testsuite latest_tag`

----------

### Require labels

#### Overview

Checks if the CNF validates that the label `app.kubernetes.io/name` is specified with some value.
Expectation: Checks if pods are using the 'app.kubernetes.io/name' label

#### Rationale

Defining and using labels help identify semantic attributes of your application or Deployment. A common set of labels allows tools to work collaboratively, while describing objects in a common manner that all tools can understand. You should use recommended labels to describe applications in a way that can be queried.

#### Remediation

Make sure to define `app.kubernetes.io/name` label under metadata for your CNF.

#### Usage

`./cnf-testsuite require_labels`

----------

### Versioned tag

#### Overview

Checks if the CNF is using a 'latest' tag instead of a semantic version using OPA Gatekeeper.
Expectation: The CNF should use an immutable tag that maps to a symantic version of the application.

#### Rationale

You should [avoid using the :latest tag](https://kubernetes.io/docs/concepts/containers/images/) when deploying containers in production as it is harder to track which version of the image is running and more difficult to roll back properly.

#### Remediation

When specifying container images, always specify a tag and ensure to use an immutable tag that maps to a specific version of an application Pod. Remove any usage of the `latest` tag, as it is not guaranteed to be always point to the same version of the image.

#### Usage

`./cnf-testsuite versioned_tag`

----------

### NodePort not used

#### Overview

Checks the CNF for any associated K8s Services that configured to expose the CNF by using a nodePort.
Expectation: The nodePort configuration field is not found in any of the CNF's services.

#### Rationale

Using node ports ties the CNF to a specific node and therefore makes the CNF less portable and scalable.

#### Remediation

Review all Helm Charts & Kubernetes Manifest files for the CNF and remove all occurrences of the nostPort field in you configuration. Alternatively, configure a service or use another mechanism for exposing your container.

#### Usage

`./cnf-testsuite nodeport_not_used`

----------

### HostPort not used

#### Overview

Checks the CNF's workload resources for any containers using the hostPort configuration field to expose the application.
Expectation: The hostPort configuration field is not found in any of the defined containers.

#### Rationale

Using host ports ties the CNF to a specific node and therefore makes the CNF less portable and scalable.

#### Remediation

Review all Helm Charts & Kubernetes Manifest files for the CNF and remove all occurrences of the hostPort field in you configuration. Alternatively, configure a service or use another mechanism for exposing your container.

#### Usage

`./cnf-testsuite hostport_not_used`

----------

### Hardcoded IP addresses in K8s runtime configuration

#### Overview

The hardcoded ip address test will scan all of the CNF's workload resources and check for any static, hardcoded ip addresses being used in the configuration.
Expectation: That no hardcoded IP addresses or subnet masks are found in the Kubernetes workload resources for the CNF.

#### Rationale

Using a hard coded IP in a CNF's configuration designates *how* (imperative) a CNF should achieve a goal, not *what* (declarative) goal the CNF should achieve.

#### Remediation

Review all Helm Charts & Kubernetes Manifest files of the CNF and look for any hardcoded usage of ip addresses. If any are found, you will need to use an operator or some other method to abstract the IP management out of your configuration in order to pass this test.

#### Usage

`./cnf-testsuite hardcoded_ip_addresses_in_k8s_runtime_configuration`

----------

### Secrets used

#### Overview

The secrets used test will scan all the Kubernetes workload resources to see if K8s secrets are being used.
Expectation: The CNF is using K8s secrets for the management of sensitive data.

#### Rationale

If a CNF uses kubernetes K8s secrets instead of unencrypted environment variables or configmaps, there is [less risk of the Secret (and its data) being exposed](https://kubernetes.io/docs/concepts/configuration/secret/) during the workflow of creating, viewing, and editing Pods.

#### Remediation

Remove any sensitive data stored in configmaps, environment variables and instead utilize K8s Secrets for storing such data.
Alternatively, you can use an operator or some other method to abstract hardcoded sensitive data out of your configuration.
The whole test passes if _any_ workload resource in the cnf uses a (non-exempt) secret. If no workload resources use a (non-exempt) secret, the test is skipped.

#### Usage

`./cnf-testsuite secrets_used`

----------

### Immutable configmap

#### Overview

The immutable configmap test will scan the CNF's workload resources and see if immutable configmaps are being used.
Expectation: Immutable configmaps are being used for non-mutable data.

#### Rationale

For clusters that extensively use ConfigMaps (at least tens of thousands of unique ConfigMap to Pod mounts),
[preventing changes](https://kubernetes.io/docs/concepts/configuration/configmap/#configmap-immutable)
to their data has the following advantages:

* protects you from accidental (or unwanted) updates that could cause applications outages
* improves performance of your cluster by significantly reducing load on kube-apiserver, by closing watches for ConfigMaps marked as immutable.

#### Remediation

Use immutable configmaps for any non-mutable configuration data.

#### Usage

`./cnf-testsuite immutable_configmap`

----------

### Kubernetes Alpha APIs **PoC**

#### Overview

This checks if a CNF uses alpha or unstable versions of Kubernetes APIs
Expectation: CNF should not use Kubernetes alpha APIs

#### Rationale

If a CNF uses alpha or undocumented APIs, the CNF is tightly coupled to an unstable platform

#### Remediation

Make sure your CNFs are not utilizing any Kubernetes alpha APIs. You can learn more about Kubernetes API versioning [here](https://bit.ly/k8s_api).

#### Usage

`./cnf-testsuite alpha_k8s_apis`

----------

## Category: 5G Tests

A 5g core is an important part of the service provider's telecommuncations offering. A cloud native 5g architecture uses immutable infrastructure, declarative configuration, and microservices when creating and hosting 5g cloud native network functions.

### Usage

All 5G: `./cnf-testsuite 5g`

----------

### SMF UPF core validator

#### Overview

Checks the pfcp heartbeat between the smf and upf to make sure it remains close to baseline.
Expectation: 5g core should continue to function during various CNF tests.

#### Rationale

A 5g core's [SMF and UPF CNFs have a hearbeat](https://www.etsi.org/deliver/etsi_ts/123500_123599/123527/15.01.00_60/ts_123527v150100p.pdf), implemented use the PFCP protocol standard, which measures if the connection between the two CNFs is active.
After measure a baseline of the heartbeat a comparison between the baseline and the performance of the heartbeat while running test functions will expose the [cloud native resilience](https://www.cncf.io/blog/2021/09/23/cloud-native-chaos-and-telcos-enforcing-reliability-and-availability-for-telcos/) of the cloud native 5g core.

#### Remediation

#### Usage

`./cnf-testsuite smf_upf_core_validator`

----------

### SUCI enabled

#### Overview

Checks to see if the 5g core supports suci concealment.
Expectation: 5g core should use suci concealment.

#### Rationale

In order to [protect identifying information](https://nickvsnetworking.com/5g-subscriber-identifiers-suci-supi/) from being sent over the network as clear text, 5g cloud native cores should implement [SUPI and SUCI concealment](https://www.etsi.org/deliver/etsi_ts/133500_133599/133514/16.04.00_60/ts_133514v160400p.pdf)

#### Remediation

#### Usage

`./cnf-testsuite suci_enabled`

----------

## Category: RAN Tests

### Usage

All RAN: `./cnf-testsuite ran`

A cloud native radio access network's (RAN) cloud native functions should use immutable infrastructure, declarative configuration, and microservices.
ORAN cloud native functions should adhere to cloud native principles while also complying with the [ORAN alliance's standards](https://www.o-ran.org/blog/o-ran-alliance-introduces-48-new-specifications-released-since-july-2021).

----------

### ORAN e2 connection

#### Overview

Checks if a RIC uses a oran compatible e2 connection.
Expectation: An ORAN RIC should use an e2 connection.

#### Rationale

*A near real-time RAN intelligent controler (RIC) uses the [E2 standard](https://wiki.o-ran-sc.org/display/RICP/E2T+Architecture) as an open, interoperable, interface to connect to [RAN-optimizated applications, onboarded as xApps](https://www.5gtechnologyworld.com/how-does-5gs-o-ran-e2-interface-work/).
The xApps use platform services available in the near-RT RIC to communicate with the downstream network functions through the E2 interface.

#### Remediation

#### Usage

`./cnf-testsuite oran_e2_connection`

----------

## Category: Platform Tests

### Usage

All platform: `./cnf-testsuite platform`

All platform hardware and scheduling: `./cnf-testsuite platform:hardware_and_scheduling`

All platform resilience: `./cnf-testsuite platform:resilience poc`

All platform security: `./cnf-testsuite platform:security`

----------

### K8s Conformance

#### Overview

Check if your platform passes the K8s conformance test.
See <https://github.com/cncf/k8s-conformance> for details on what is tested.
Expectation: The K8s cluster passes the K8s conformance tests

#### Rationale

A Vendor's Kubernetes Platform should pass [Kubernetes Conformance](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/conformance-tests.md). This ensures that the platform offering meets the same required APIs, features & interoperability expectations as in open source community versions of K8s.
Applications that can operate on a [Certified Kubernetes](https://www.cncf.io/certification/software-conformance/) should be cross-compatible with any other Certified Kubernetes platform.

#### Remediation

Check that [Sonobuoy](https://github.com/vmware-tanzu/sonobuoy) can be successfully run and passes without failure on your platform. Any failures found by Sonobuoy will provide debug and remediation steps required to get your K8s cluster into a conformant state.

#### Usage

`./cnf-testsuite k8s_conformance`

----------

### ClusterAPI enabled

#### Overview

Checks the platforms Kubernetes Nodes to see if they were instansiated by ClusterAPI.
Expectation: The cluster has Cluster API enabled which manages at least one Node.

#### Rationale

A Kubernetes Platform should leverage [Cluster API](https://cluster-api.sigs.k8s.io/) to ensure that best-practices are followed for both bootstrapping & cluster lifecycle management. Kubernetes is a complex system that relies on several components being configured correctly, maintaining an in-house lifecycle management system for kubernetes is unlikey to meet best practice guideline unless significant resources are deticated to it.

#### Remediation

Enable ClusterAPI and start using it to manage the provisioning and lifecycle of your Kubernetes clusters.

#### Usage

`./cnf-testsuite clusterapi_enabled`

----------

### OCI Compliant

#### Overview

Inspects all worker nodes and checks if the run-time being used for scheduling is OCI compliant.
Expectation: All worker nodes are using an OCI compliant run-time.

#### Rationale

The [OCI Initiative](https://opencontainers.org/) was created to ensure that runtimes conform  to both the runtime-spec and image-spec. These two specifications outline how a “filesystem bundle” is unpacked on disk and that the image itself contains sufficient information to launch the application on the target platform.
As a best practice, your platform must use an OCI compliant runtime, this ensures that the runtime used is cross-compatible and supports interoperability with other runtimes. This means that workloads can be freely moved to other runtimes and prevents vendor lock in.

#### Remediation

Check if your Kuberentes Platform is using an [OCI Compliant Runtime](https://opencontainers.org/). If you platform is not using an OCI Compliant Runtime, you'll need to switch to a new runtime that is OCI Compliant in order to pass this test.

#### Usage

`./cnf-testsuite platform:oci_compliant`

----------

### (POC) Worker reboot recovery

#### Overview

**WARNING**: this is a destructive test and will reboot your _host_ node! Do not run this unless you have completely separate cluster, e.g. development or test cluster.

Run node failure test which forces a reboot of the Node ("host system"). The Pods on that node should be rescheduled to a new Node.
Expectation: Pods should reschedule after a node failure.

#### Rationale

Cloud native systems should be self-healing. To follow cloud-native best practices your platform should be  resiliant and reschedule all workloads when such node failures occur.

#### Remediation

Reboot a worker node in your Kubernetes cluster verify that the node can recover and re-join the cluster in a schedulable state. Workloads should also be rescheduled to the node once it's back online.

#### Usage

`./cnf-testsuite platform:worker_reboot_recovery poc destructive`

----------

### Cluster admin

#### Overview

Check which subjects have cluster-admin RBAC permissions – either by being bound to the cluster-admin clusterrole, or by having equivalent high privileges.
Expectation: The [cluster admin role should not be bound to a Pod](https://bit.ly/C0035_cluster_admin)

#### Rationale

Role-based access control (RBAC) is a key security feature in Kubernetes. RBAC can restrict the allowed actions of the various identities in the cluster. Cluster-admin is a built-in high privileged role in Kubernetes. Attackers who have permissions to create bindings and cluster-bindings in the cluster can create a binding to the cluster-admin ClusterRole or to other high privileges roles.
As a best practice, a principle of least privilege should be followed and cluster-admin privilege should only be used on an as-needed basis.

#### Remediation

You should apply least privilege principle. Make sure cluster admin permissions are granted only when it is absolutely necessary. Don't use subjects with high privileged permissions for daily operations.

#### Usage

`./cnf-testsuite platform:cluster_admin`

----------

### Control plane hardening

#### Overview

Checks if the insecure-port flag is set for the K8s API Server.
Expectation: That the the k8s control plane is secure and not hosted on an [insecure port](https://bit.ly/C0005_Control_Plane)

#### Rationale

The control plane is the core of Kubernetes and gives users the ability to view containers, schedule new Pods, read Secrets, and execute commands in the cluster. Therefore, it should be protected. It is recommended to avoid control plane exposure to the Internet or to an untrusted network and require TLS encryption.

#### Remediation

Set the insecure-port flag of the API server to zero.
See more at [ARMO-C0005](https://bit.ly/C0005_Control_Plane)

#### Usage

`./cnf-testsuite platform:control_plane_hardening`

----------

### Tiller images

#### Overview

Checks if a Helm v2 / Tiller image is deployed and used on the platform.
Expectation: The platform should be using Helm v3+ without Tiller.

#### Rationale

Tiller, found in Helm v2, has known security challenges. It requires administrative privileges and acts as a shared resource accessible to any authenticated user. Tiller can lead to privilege escalation as restricted users can impact other users. It is recommend to use Helm v3+ which does not contain Tiller for these reasons

#### Remediation

Switch to using Helm v3+ and make sure not to pull any images with name tiller in them

#### Usage

`./cnf-testsuite platform:helm_tiller`

----------

### ConfigMaps encrypted

#### Overview

Test verifies that Kubernetes ConfigMaps are encrypted at rest in etcd. This ensures that sensitive data stored in ConfigMaps is not accessible in plain text, meeting basic security and compliance requirements. Expectation: ConfigMaps should be encrypted to ensure sensitive data is not stored in plain text.

#### Rationale

ConfigMaps encryption is not enabled by default in kubernetes environment. Since ConfigMaps can contain sensitive information, it is recommended to enable encryption to protect these values. To encrypt ConfigMaps stored in etcd, Kubernetes supports encryption at rest, which ensures that key-value pairs are no longer stored in plain text.

#### Remediation

Check version of ETCDCTL in etcd pod, it should be v3 or higher, as earlier versions lack support for encryption features. To enable encryption of ConfigMaps, create an EncryptionConfiguration file for the API server and reference it in the cluster configuration. Optionally, encryption can be enabled manually by editing the kube-apiserver manifest.

#### Usage

To run the test to verify if ConfigMaps are encrypted:

`./cnf-testsuite platform:verify_configmaps_encryption`

----------

### Secrets encrypted

#### Overview

Test verifies that Kubernetes Secrets are encrypted at rest in etcd. This ensures that sensitive information stored in Secrets is not accessible in plain text, aligning with security requirements. Expectation: Secrets should be encrypted to ensure sensitive data is not stored in plain text.

#### Rationale

By default, Kubernetes stores Secrets in etcd without encryption. Since Secrets contain sensitive information, it is recommended to encrypt these values. Enabling encryption in etcd ensures that secret values are not stored in plain text, protecting them from unauthorized access.

#### Remediation

Check version of ETCDCTL in etcd pod, it should be v3 or higher, as earlier versions lack support for encryption features. To enable encryption of Secrets, create an EncryptionConfiguration file for the API server and reference it in the cluster configuration. Optionally, encryption can be enabled manually by editing the kube-apiserver manifest.

#### Usage

To run the test to verify if Secrets are secured:

`./cnf-testsuite platform:verify_secrets_encryption`
