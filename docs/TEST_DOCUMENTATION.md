# CNTi Test Suite test documentation

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

   [[Container socket mounts]](#container-socket-mounts) | [[Privileged Containers]](#privileged-containers) | [[External IPs]](#external-ips) | [[SELinux Options]](#selinux-options) | [[Sysctls]](#sysctls) | [[Privilege escalation]](#privilege-escalation) | [[Seccomp profile]](#seccomp-profile) | [[Symlink file system]](#symlink-file-system) | [[Application credentials]](#application-credentials) | [[Host network]](#host-network) | [[Service account mapping]](#service-account-mapping) | [[Ingress and Egress blocked]](#ingress-and-egress-blocked) | [[Insecure capabilities]](#insecure-capabilities) | [[Non-root containers]](#non-root-containers) | [[Host PID/IPC privileges]](#host-pidipc-privileges) | [[Linux hardening]](#linux-hardening) | [[CPU limits]](#cpu-limits) | [[Memory limits]](#memory-limits) | [[Immutable File Systems]](#immutable-file-systems) | [[HostPath Mounts]](#hostpath-mounts)

* [**Category: Configuration Tests**](#category-configuration-tests)

   [[Default namespaces]](#default-namespaces) | [[Latest tag]](#latest-tag) | [[Require labels]](#require-labels) | [[Versioned tag]](#versioned-tag) | [[NodePort not used]](#nodeport-not-used) | [[HostPort not used]](#hostport-not-used) | [[Hardcoded IP addresses in K8s runtime configuration]](#hardcoded-ip-addresses-in-k8s-runtime-configuration) | [[Secrets used]](#secrets-used) | [[Immutable configmap]](#immutable-configmap) | [[Kubernetes Alpha APIs]](#kubernetes-alpha-apis) | [[Operator installed]](#operator-installed)

----------

## Category: Compatibility, Installability and Upgradability Tests

CNFs should work with any Certified Kubernetes product and any CNI-compatible network that meet their functionality requirements. The CNTI Test Suite will check for usage of standard, in-band deployment tools such as Helm (version 3) charts. The CNTI Test Suite checks to see if CNFs support horizontal scaling (across multiple machines) and vertical scaling (between sizes of machines) by using the native K8s [kubectl](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources).

Service providers have historically had issues with the installability of vendor network functions. This category tests the installability and lifecycle management (the create, update, and delete of network applications) against widely used K8s installation solutions such as Helm.

### Usage

All compatibility: `./cnti-testsuite compatibility`

----------

### Increase decrease capacity

#### Overview

HPA (horizontal pod autoscale) will autoscale replicas to accommodate when there is an increase of CPU, memory or other configured metrics to prevent disruption by allowing more requests
by balancing out the utilisation across all of the pods.
Decreasing replicas works the same as increase but rather scale down the number of replicas when the traffic decreases to the number of pods that can handle the requests.
You can read more about horizontal pod autoscaling to create replicas [here](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) and in the [K8s scaling cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources).
The test scales each Deployment and StatefulSet from its deployed replica count up by two, then back to the deployed count, and leaves the CNF as it found it.
Expectation: The number of replicas for a Pod increases and then decreases.

#### Rationale

A CNF should be able to increase and decrease its capacity without running into errors.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/); [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Check out the kubectl docs for how to [manually scale your cnf.](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources)
Also here is some info about [things that could cause failures.](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#failed-deployment)

#### Usage

`./cnti-testsuite increase_decrease_capacity`

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

Checks if the Pod can be upgraded to a new software version, then restored back to the original software version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) and [Kubectl Rollout Undo](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout) commands.
Expectation: The CNF Software version can be successfully incremented, then rolled back.
The test needs the version to move to from the `container_names` section of `cnti-testsuite.yaml` (`rollback_from_tag`); a container without it is left out with a remediation, and the test is skipped when no container has one. A rollout that does not complete is reported per resource with the image and the reason.

#### Rationale

K8s best practice is to allow [K8s to manage the rolling back](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment) of an application resource instead of having operators manually rolling back the resource by using something like blue/green deploys.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

Ensure that you can upgrade your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command, then rollback the upgrade using the [Kubectl Rollout Undo](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout) command.

#### Usage

`./cnti-testsuite rollback`

----------

### Rolling version change

#### Overview

Checks if the Pod can be rolled back to the original software version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) to perform a rollback.
Expectation: The CNF Software version is successfully rolled back to its original version.
The test needs the version to move to from the `container_names` section of `cnti-testsuite.yaml` (`rolling_version_change_test_tag`); a container without it is left out with a remediation, and the test is skipped when no container has one. A rollout that does not complete is reported per resource with the image and the reason.

#### Rationale

(update, version change, downgrade): K8s best practice for version/installation management (lifecycle management) of applications is to have [K8s track the version of the manifest information](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment) for the resource (deployment, pod, etc) internally.
Whenever a rollback is needed the resource will have the exact manifest information that was tied to the application when it was deployed.
This adheres the principles driving immutable infrastructure and declarative specifications.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

Ensure that you can successfully rollback the software version of your CNF by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnti-testsuite rolling_version_change`

----------

### Rolling update

#### Overview

Checks if the Pod can be upgraded to a new software version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-)
Expectation: The CNF Software version can be successfully incremented.
The test needs the version to move to from the `container_names` section of `cnti-testsuite.yaml` (`rolling_update_test_tag`); a container without it is left out with a remediation, and the test is skipped when no container has one. A rollout that does not complete is reported per resource with the image and the reason.

#### Rationale

See rolling version change.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

Ensure that you can successfully perform a rolling upgrade of your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnti-testsuite rolling_update`

----------

### Rolling downgrade

#### Overview

Checks if the Pod can be rolled back older software version(Older than the original software version) by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) to perform a downgrade.
Expectation: The CNF Software version is successfully downgraded to a software version older than the original installation version.
The test needs the version to move to from the `container_names` section of `cnti-testsuite.yaml` (`rolling_downgrade_test_tag`); a container without it is left out with a remediation, and the test is skipped when no container has one. A rollout that does not complete is reported per resource with the image and the reason.

#### Rationale

See rolling version change.

Sources: [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

#### Remediation

Ensure that you can successfully change the software version of your CNF back to an older version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

#### Usage

`./cnti-testsuite rolling_downgrade`

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

Checks whether any deprecated Kubernetes features (API versions, annotations, fields) are used by the CNF. The CNF's manifest is applied to the cluster as a server-side dry-run, and the deprecation warnings the API server returns are reported, each attributed to the resource that carries it. The API server is the authority on what is deprecated in the Kubernetes version the CNF runs on.

#### Rationale

A CNF should avoid using any deprecated features that are scheduled for removal. It should transition to stable and
actively maintained alternatives.

Sources: [Kubernetes API deprecation policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Ensure that the CNF is not using deprecated Kubernetes features. If any are detected, follow tips from warning message displayed by testsuite and/or consult [Deprecated API Migration Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/).

#### Usage

`./cnti-testsuite deprecated_k8s_features`

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

Measures, for every workload resource of the CNF, how long its slowest pod took from its containers starting to reporting Ready, as recorded in the pod's status; image pulls and scheduling are excluded. Each workload is reported with its slowest pod and time, and each one over the limit is a finding. The limit is 30 seconds unless the CNF sets `startup_time_max_seconds` in `cnti-testsuite.yaml`.
Expectation: Every workload of the CNF is Ready within 30 seconds of its containers starting.

#### Rationale

Start-up time bounds how fast a CNF can scale out, recover from a pod loss and roll a new version; a pod that takes minutes to become Ready holds up every one of those. Long start-ups usually come from work done in the start-up path that belongs elsewhere, or from a fixed [readiness delay](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) standing in for a real readiness check; Kubernetes provides a startupProbe for the genuinely slow starters so that liveness settings need not be relaxed. Sources: [Kubernetes probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

Sources: [Kubernetes probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

#### Remediation

Move work out of the start-up path (lazy initialisation, pre-built caches, smaller images), gate readiness on what the service actually needs rather than on a fixed initial delay, and use a startupProbe for components that genuinely need longer. Set `startup_time_max_seconds` when the CNF's design justifies a longer limit.

#### Usage

`./cnti-testsuite reasonable_startup_time`

----------

### Single Process Type in One Container

#### Overview

This verifies that there is only one application process type within one container. This does not count against child processes of the same type, nor against the container's init/supervisor process. For example, nginx or httpd could have a parent process and then 10 child processes, but if both nginx and httpd were running, this test would fail.
Expectation: CNF container has one application process type

The container's own init/supervisor process (PID 1) is not counted as an application process type, regardless of which init system it uses. Whether that init system is a recommended, specialized one (e.g. tini, dumb-init, s6) is evaluated separately by the `specialized_init_system` test — using a home-grown init will not fail this test, but it is reported in the test output and results file.

#### Rationale

A microservice should have only one application process (or set of parent/child processes of the same type), optionally managed by an init/supervisor. The microservice should not spawn other process types (e.g., executables) as a way to contribute to the workload but rather should interact with other processes through a microservice API.

Sources: [CNTi CBPP-0005, single concern per container](https://github.com/lfn-cnti/bestpractices/blob/main/doc/cbpps/0005-single-concern-per-container.md); [Docker, running multiple services in a container](https://docs.docker.com/engine/containers/multi-service_container/); [The Twelve-Factor App, processes](https://12factor.net/processes).

#### Remediation

Ensure that there is only one process type within a container. This does not count against child processes, e.g., nginx or httpd could be a parent process with 10 child processes and pass this test, but if both nginx and httpd were running, this test would fail.

#### Usage

`./cnti-testsuite single_process_type`

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

Finds the databases among the CNF's workloads (MariaDB/MySQL, PostgreSQL, MongoDB, Redis, Cassandra, etcd, by image name or port) and watches each one's connections for a minute to see which CNF workloads connect to it. A workload counts as a service when a Service of the CNF selects its pods; other clients (jobs, batch workers) are listed but do not count. Every database is reported with the services that connected to it, and a database with two or more services is a finding. N/A when the CNF has no database.
Expectation: No database of the CNF is used by more than one service.

#### Rationale

A database shared by two services couples them: a schema change made for one breaks the other, they must upgrade in lock step and neither can be scaled, replaced or rolled back alone, which defeats the point of splitting them. This is the [integration database](https://martinfowler.com/bliki/IntegrationDatabase.html) anti-pattern; a service should own its data and expose it through its API. Sources: [Fowler, IntegrationDatabase](https://martinfowler.com/bliki/IntegrationDatabase.html); [microservices.io, database per service](https://microservices.io/patterns/data/database-per-service.html); [CBPP-0002 Microservices](https://github.com/lfn-cnti/bestpractices/blob/main/cbpps/cbpp-0002.md).

Sources: [The Twelve-Factor App, backing services](https://12factor.net/backing-services); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Give each service its own database (or its own schema with no cross-service access) and expose the data through the owning service's API instead of a shared database.

#### Usage

`./cnti-testsuite shared_database`

----------

### Specialized Init Systems

#### Overview

This tests if containers in pods use a specialized init system as their PID 1 process: tini (including tini-static and docker-init), dumb-init, catatonit, or s6-overlay (whose PID 1 is s6-svscan). The check is on the executable's name, not on any part of its path.
Expectation: Container images should use specialized init systems for containers.

#### Rationale

There are proper init systems and sophisticated supervisors that can be run inside of a container. Both of these systems properly reap and pass signals. Sophisticated supervisors are considered overkill because they take up too many resources and are sometimes too complicated. Some examples of sophisticated supervisors are: supervisord, monit, and runit. Proper init systems are smaller than sophisticated supervisors and therefore suitable for containers. Some of the proper container init systems are tini, dumb-init, catatonit, and s6-overlay.

Sources: [Docker, `--init` for signal handling and zombie reaping](https://docs.docker.com/reference/cli/docker/container/run/#init); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

#### Remediation

Use init systems that are purpose-built for containers like tini, dumb-init, catatonit, s6-overlay.

#### Usage

`./cnti-testsuite specialized_init_system`

----------

### Sigterm Handled

#### Overview

This tests if the PID 1 process of containers handles SIGTERM. SIGTERM is sent to each container's PID 1 and the process must terminate within the pod's `terminationGracePeriodSeconds` (default 30 s). When PID 1 supervises child processes, the children are judged instead: they must receive the forwarded signal and terminate. Containers that cannot be traced are reported as skipped and do not fail the test.
Expectation: Sigterm is handled by PID 1 process of containers.

#### Rationale

The Linux kernel handles signals differently for the process that has PID 1 than it does for other processes. Signal handlers aren't automatically registered for this process, meaning that signals such as SIGTERM or SIGINT will have no effect by default. By default, one must kill processes by using SIGKILL, preventing any graceful shutdown. Depending on the application, using SIGKILL can result in user-facing errors, interrupted writes (for data stores), or unwanted alerts in a monitoring system.

Sources: [Kubernetes pod lifecycle, termination](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination); [The Twelve-Factor App, disposability](https://12factor.net/disposability).

#### Remediation

Make the PID 1 container process to handle SIGTERM; enable process namespace sharing in Kubernetes or use specialized Init system.

#### Usage

`./cnti-testsuite sig_term_handled`

----------

### Zombie Handled

#### Overview

This tests if the PID 1 process of containers handles/reaps zombie processes.
The test injects a probe into every container that creates an orphaned child process; the test is skipped when the probe cannot be injected (for example into a read-only root filesystem).
Expectation: Zombie processes are handled/reaped by PID 1 process of containers.

#### Rationale

Classic init systems such as systemd are also used to remove (reap) orphaned, zombie processes. Orphaned processes — processes whose parents have died - are reattached to the process that has PID 1, which should reap them when they die. A normal init system does that. But in a container, this responsibility falls on whatever process has PID 1. If that process doesn't properly handle the reaping, you risk running out of memory or some other resources.

Sources: [Docker, `--init` for signal handling and zombie reaping](https://docs.docker.com/reference/cli/docker/container/run/#init); [Google Cloud, best practices for building containers](https://cloud.google.com/architecture/best-practices-for-building-containers).

#### Remediation

Make the PID 1 container process to handle/reap zombie processes; enable process namespace sharing in Kubernetes or use specialized Init system.

#### Usage

`./cnti-testsuite zombie_handled`

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

A node is drained and workload resources rescheduled to another node, passing with a liveness and readiness check. This will skip when the cluster has fewer than two schedulable nodes, when the workload has no scheduled pod, or when no schedulable node is left to move the chaos operator onto.
Measurement: LitmusChaos experiment [node-drain](https://litmuschaos.github.io/litmus/experiments/categories/nodes/node-drain/); the Litmus version is in the results file's `tools`.
Expectation: All workload resources are successfully rescheduled onto other available node(s).

#### Rationale

No CNF should fail because of stateful configuration. A CNF should function properly if it is rescheduled on other nodes.
This test will remove resources which are running on a target node and reschedule them on another node.

Sources: [Safely drain a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/); [Kubernetes disruptions and PodDisruptionBudgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/).

#### Remediation

Ensure that your CNF can be successfully rescheduled when a node fails or is [drained](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)

#### Usage

`./cnti-testsuite node_drain`

----------

### No local volume configuration

#### Overview

Checks every persistent volume claim the CNF's workloads mount: the PersistentVolume it is bound to must not be a local volume (`spec.local.path`), which ties the workload to one node and its disk. Each local volume is reported with the workload, the claim and the path; a claim bound to no PersistentVolume leaves the storage type undetermined and the test is skipped rather than passed.
Expectation: Local storage should not be used or configured.

#### Rationale

A CNF should refrain from using the [local storage class](https://kubernetes.io/docs/concepts/storage/storage-classes/#local)

Sources: [Kubernetes persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Ensure that your CNF isn't using any persistent volumes that use a ["local"] mount point.

#### Usage

`./cnti-testsuite no_local_volume_configuration`

----------

### Elastic volumes

#### Overview

This checks for elastic persistent volumes in use by the CNF.
If no persistent volumes are found, the test is skipped.
Expectation: Elastic persistent volumes should be configured for statefulness.

#### Rationale

A cnf that uses elastic volumes can be rescheduled to other nodes by the orchestrator easily

Sources: [Kubernetes persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Setup and use elastic persistent volumes instead of local storage.

#### Usage

`./cnti-testsuite elastic_volumes`

----------

### Database persistence

#### Overview

This checks if elastic volumes and stateful sets are used for MySQL databases. If no MySQL database is found, the test is skipped.
Expectation: Elastic volumes and or statefulsets should be used for databases to maintain a minimum resilience level in K8s clusters.

#### Rationale

When a traditional database such as mysql is configured to use statefulsets, it allows the database to use a persistent identifier that it maintains across any rescheduling.
Persistent Pod identifiers make it easier to match existing volumes to the new Pods that have been rescheduled.
<https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/>

Sources: [Kubernetes persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/); [The Twelve-Factor App, backing services](https://12factor.net/backing-services).

#### Remediation

Select a database configuration that uses statefulsets and elastic storage volumes.

#### Usage

`./cnti-testsuite database_persistence`

----------

## Category: Reliability, Resilience and Availability Tests

[Cloud Native Definition](https://github.com/cncf/toc/blob/master/DEFINITION.md) requires systems to be Resilient to failures inevitable in cloud environments. CNF Resilience should be tested to ensure CNFs are designed to deal with non-carrier-grade shared cloud HW/SW platform

Cloud native systems promote resilience by putting a high priority on testing individual components (chaos testing) as they are running (possibly in production).
[Reliability in traditional telecommunications](https://vmblog.com/archive/2021/09/15/cloud-native-chaos-and-telcos-enforcing-reliability-and-availability-for-telcos.aspx) is handled differently than in Cloud Native systems. Cloud native systems try to address reliability (MTBF) by having the subcomponents have higher availability through higher serviceability (MTTR) and redundancy. For example, having ten redundant subcomponents where seven components are available and three have failed will produce a top level component that is more reliable (MTBF) than a single component that "never fails" in the cloud native world.

### Usage

All resilience: `./cnti-testsuite resilience`

----------

### CNF under network latency

#### Overview

[This experiment](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-latency/) causes network degradation without the pod being marked unhealthy/unworthy of traffic by kube-proxy (unless you have a liveness probe of sorts that measures latency and restarts/crashes the container). The idea of this experiment is to simulate issues within your pod network OR microservice communication across services in different availability zones/regions etc.
The applications may stall or get corrupted while they wait endlessly for a packet. The experiment limits the impact (blast radius) to only the traffic you want to test by specifying IP addresses or application information. This experiment will help to improve the resilience of your services over time.
Measurement: LitmusChaos experiment [pod-network-latency](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-latency/); the Litmus version is in the results file's `tools`.
Expectation: The CNF should continue to function when network latency occurs
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.

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

----------

### CNF with host disk fill

#### Overview

[This experiment](https://litmuschaos.github.io/litmus/experiments/categories/pods/disk-fill/) stresses the disk with continuous and heavy IO to cause degradation in the shared disk. This experiment also reduces the amount of scratch space available on a node which can lead to a lack of space for newer containers to get scheduled. This can cause (Kubernetes gives up by applying an "eviction" taint like "disk-pressure") a wholesale movement of all pods to other nodes.
Measurement: LitmusChaos experiment [disk-fill](https://litmuschaos.github.io/litmus/experiments/categories/pods/disk-fill/); the Litmus version is in the results file's `tools`.
Expectation: The CNF should continue to function when disk fill occurs and pods should not be evicted to another node.
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.
A workload whose containers all mount a read-only root file system cannot be filled at all, which is the property this experiment probes, so it passes without the fault being injected; the reason is recorded in the test details. In a workload that mixes read-only and writable containers, the fault is injected into a writable one.

#### Rationale

Disk Pressure is a scenario we find in Kubernetes applications that can result in the eviction of the application replica and impact its delivery. Such scenarios can still occur despite whatever availability aids K8s provides. These problems are generally referred to as "Noisy Neighbour" problems.

Sources: [LitmusChaos disk-fill fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/disk-fill/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient and doesn't stall when heavy IO causes a degradation in storage resource availability.

#### Usage

`./cnti-testsuite disk_fill`

----------

### Pod delete

#### Overview

[This experiment](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-delete/) helps to simulate such a scenario with forced/graceful pod failure on specific or random replicas of an application resource and checks the deployment sanity (replica availability & uninterrupted service) and recovery workflow of the application.
Measurement: LitmusChaos experiment [pod-delete](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-delete/); the Litmus version is in the results file's `tools`.
Expectation: The CNF should continue to function when pod delete occurs
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.

#### Rationale

In a distributed system like Kubernetes, application replicas may not be sufficient to manage the traffic (indicated by SLIs) when some replicas are unavailable due to any failure (can be system or application). The application needs to meet the SLO (service level objectives) for this. It's imperative that the application has defenses against this sort of failure to ensure that the application always has a minimum number of available replicas.

Sources: [LitmusChaos pod-delete fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-delete/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient and doesn't fail on a forced/graceful pod failure on specific or random replicas of an application.

#### Usage

`./cnti-testsuite pod_delete`

----------

### Memory hog

#### Overview

The [pod-memory hog](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-memory-hog/) experiment launches a stress process within the target container - which can cause either the primary process in the container to be resource constrained in cases where the limits are enforced OR eat up available system memory on the node in cases where the limits are not specified.
Measurement: LitmusChaos experiment [pod-memory-hog](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-memory-hog/); the Litmus version is in the results file's `tools`.
Expectation: The CNF should continue to function when pod memory hog occurs
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.

#### Rationale

If the memory policies for a CNF are not set and granular, containers on the node can be killed based on their oom_score and the QoS class a given pod belongs to (best-effort ones are first to be targeted). This eval is extended to all pods running on the node, thereby causing a bigger blast radius.

Sources: [LitmusChaos pod-memory-hog fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-memory-hog/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to heavy memory usage and can maintain some level of availability.

#### Usage

`./cnti-testsuite pod_memory_hog`

----------

### IO Stress

#### Overview

The [pod-io stress](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-io-stress/) experiment the disk with continuous and heavy IO to cause degradation in reads/writes by other microservices that use this shared disk.
Measurement: LitmusChaos experiment [pod-io-stress](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-io-stress/); the Litmus version is in the results file's `tools`.
Expectation: The CNF should continue to function when pod io stress occurs
The fault is injected through the node's container runtime: the suite detects the runtime (docker, containerd or CRI-O) from the nodes and probes the usual socket locations on a node, and `CNTI_TESTSUITE_CONTAINER_RUNTIME_SOCKET` overrides the path. The test is not applicable when the runtime is unsupported or no socket is found. A workload that owns no pod is listed in the details and left out.
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.
A workload whose containers all mount a read-only root file system cannot be stressed at all, which is the property this experiment probes, so it passes without the fault being injected; the reason is recorded in the test details. In a workload that mixes read-only and writable containers, the fault is injected into a writable one.

#### Rationale

Stressing the disk with continuous and heavy IO can cause degradation in reads/writes by other microservices that use this
shared disk.  Scratch space can be used up on a node which leads to the lack of space for newer containers to get scheduled which
causes a movement of all pods to other nodes. This test determines the limits of how a CNF uses its storage device.

Sources: [LitmusChaos pod-io-stress fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-io-stress/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to continuous and heavy disk IO load and can maintain some level of availability

#### Usage

`./cnti-testsuite pod_io_stress`

----------

### Network corruption

#### Overview

The [pod-network corruption](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-corruption/) experiment injects packet corruption on the CNF by starting a traffic control (tc) process with netem rules to add egress packet corruption.
Measurement: LitmusChaos experiment [pod-network-corruption](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-corruption/); the Litmus version is in the results file's `tools`.
Expectation: The CNF should be resilient to a lossy/flaky network and should continue to provide some level of availability.
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.

#### Rationale

A higher quality CNF should be resilient to a lossy/flaky network.  This test injects packet corruption on the specified CNF's container by
starting a traffic control (tc) process with netem rules to add egress packet corruption.

Sources: [LitmusChaos pod-network-corruption fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-corruption/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to a lossy/flaky network and can maintain a level of availability.

#### Usage

`./cnti-testsuite pod_network_corruption`

----------

### Network duplication

#### Overview

The [pod-network duplication](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-duplication/) experiment injects network duplication into the CNF by starting a traffic control (tc) process with netem rules to add egress delays.
Measurement: LitmusChaos experiment [pod-network-duplication](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-duplication/); the Litmus version is in the results file's `tools`.
Expectation: The CNF should continue to function and be resilient to a duplicate network.
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.

#### Rationale

A higher quality CNF should be resilient to erroneously duplicated packets. This test injects network duplication on the specified container
by starting a traffic control (tc) process with netem rules to add egress delays.

Sources: [LitmusChaos pod-network-duplication fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-network-duplication/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to erroneously duplicated packets and can maintain a level of availability.

#### Usage

`./cnti-testsuite pod_network_duplication`

----------

### Pod DNS errors

#### Overview

The [pod-dns error](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-dns-error/) experiment injects chaos to disrupt DNS resolution in kubernetes pods and causes loss of access to services by blocking DNS resolution of hostnames/domains.
Measurement: LitmusChaos experiment [pod-dns-error](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-dns-error/); the Litmus version is in the results file's `tools`.
Expectation: That the CNF doesn't crash is resilient to DNS resolution failures.
Litmus can only target Deployments, StatefulSets and DaemonSets: a bare Pod or ReplicaSet is listed in the test details and left out, and the test is not applicable when nothing else can be targeted.

#### Rationale

A CNF should be resilient to name resolution (DNS) disruptions within the kubernetes pod. This ensures that at least some application availability will be maintained if DNS resolution fails.

Sources: [LitmusChaos pod-dns-error fault](https://litmuschaos.github.io/litmus/experiments/categories/pods/pod-dns-error/); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Ensure that your CNF is resilient to DNS resolution failures and can maintain a level of availability.

#### Usage

`./cnti-testsuite pod_dns_error`

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

## Category: Observability and Diagnostic Tests

In order to maintain, debug, and have insight into a production environment that is protected (versioned, kept in source control, and changed only by using a deployment pipeline), its infrastructure elements must have the property of being observable. This means these elements must externalize their internal states in some way that lends themselves to metrics, tracing, and logging.

### Usage

All observability: `./cnti-testsuite observability`

----------

### Use stdout/stderr for logs

#### Overview

This checks and verifies that STDOUT/STDERR logging is configured for the CNF. The last log lines of every pod of each workload resource are read; a resource passes when any of its pods has written to stdout/stderr. Pods whose logs cannot be read yet (not scheduled, container still starting) are reported and left out of the verdict; the test is skipped when no pod could be read.
Expectation: Resource output logs should be sent to STDOUT/STDERR

#### Rationale

By sending logs to standard out/standard error [logs will be treated like event streams](https://12factor.net/) as recommended by 12 factor apps principles.

Sources: [The Twelve-Factor App, logs](https://12factor.net/logs); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Make sure applications and CNF's are sending log output to STDOUT and or STDERR.

#### Usage

`./cnti-testsuite log_output`

----------

### Prometheus installed

#### Overview

Finds the [Prometheus](https://prometheus.io/) server in the cluster (a pod running a `prometheus` process and the Service in front of it), reads its active targets, and checks that every workload of the CNF has a pod among them. The details name the server, the URL its targets API answered at and, per workload, the scrape URL and target health; a workload no target scrapes is a finding. Not applicable, with the pods and URLs probed in the details, when no Prometheus server answers: nothing scrapes the CNF in that cluster.
Expectation: The CNF is configured and sending metrics to a Prometheus server.

#### Rationale

Recording metrics within a cloud native deployment is important because it gives the maintainer of a cluster of hundreds or thousands of services the ability to pinpoint [small anomalies](https://about.gitlab.com/blog/2018/09/27/why-all-organizations-need-prometheus/), such as those that will eventually cause a failure.

Sources: [OpenMetrics specification](https://github.com/prometheus/OpenMetrics/blob/main/specification/OpenMetrics.md); [CNCF Cloud Native Definition](https://github.com/cncf/toc/blob/main/DEFINITION.md).

#### Remediation

Install and configure Prometheus for your CNF.

#### Usage

`./cnti-testsuite prometheus_traffic`

----------

### Routed logs

#### Overview

Checks for presence of a Unified Logging Layer and if the CNFs logs are being captured by the Unified Logging Layer. fluentd and fluentbit are currently supported.
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

Checks, through Kubescape control C-0013 (Non-root containers), that no container of the CNF runs as root or can become root: `runAsNonRoot` is true, or `runAsUser`/`runAsGroup` are set to non-root IDs, at the pod or container level. Whether privilege escalation is allowed is checked separately by the `privilege_escalation` test.
Read more at [ARMO-C0013](https://bit.ly/2Zzlts3)
Measurement: Kubescape control [C-0013](https://hub.armosec.io/docs/c-0013) (Non-root containers) of the NSA framework; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should run with non-root user and allowPrivilegeEscalation should be set to false.

#### Rationale

Container engines allow containers to run applications as a non-root user with non-root group membership. Typically, this non-default setting is configured when the container image is built. Alternatively, Kubernetes can load containers into a Pod with SecurityContext:runAsUser specifying a non-zero user. While the runAsUser directive effectively forces non-root execution at deployment, [NSA and CISA encourage developers](https://hub.armo.cloud/docs/c-0013) to build container applications to execute as a non-root user. Having non-root execution integrated at build time provides better assurance that applications will function correctly without root privileges.

Sources: [CNTi CBPP-0002, non-root containers](https://github.com/lfn-cnti/bestpractices/blob/main/doc/cbpps/0002-no-root-in-containers.md); [Pod Security Standards, restricted](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted); [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes).

#### Remediation

If your application does not need root privileges, set `runAsNonRoot: true`, or set `runAsUser` and `runAsGroup` to IDs of 1000 or higher, under the pod or container securityContext.

#### Usage

`./cnti-testsuite non_root_containers`

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

Checks, through Kubescape control C-0048 (HostPath mount), whether any pod of the CNF mounts a hostPath volume. Any hostPath mount is reported, read-only ones included: a host directory mounted into a container is a path to the underlying host either way.
Read more at [ARMO-C0045](https://bit.ly/3EvltIL)
Measurement: Kubescape control [C-0048](https://hub.armosec.io/docs/c-0048) (HostPath mount) scanned on its own; the scanner and regolibrary versions are in the results file's `tools`.
Expectation: Containers should not have hostPath mounts

#### Rationale

[hostPath mount](https://hub.armo.cloud/docs/c-0006) can be used by attackers to get access to the underlying host and thus break from the container to the host. (See “3: Writable hostPath mount” for details).

Sources: [Pod Security Standards, baseline](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline); [Kubernetes volumes](https://kubernetes.io/docs/concepts/storage/volumes/); [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final).

#### Remediation

Refrain from using a hostPath mount.

#### Usage

`./cnti-testsuite hostpath_mounts`

----------

## Category: Configuration Tests

Configuration should be managed in a declarative manner, using [ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/), [Operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/), or other [declarative interfaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/#understanding-kubernetes-objects).

Declarative APIs for an immutable infrastructure are anything that configures the infrastructure element. This declaration can come in the form of a YAML file or a script, as long as the configuration designates the desired outcome, not how to achieve said outcome.

> "Because it describes the state of the world, declarative configuration does not have to be executed to be understood. Its impact is concretely declared. Since the effects of declarative configuration can be understood before they are executed, declarative configuration is far less error-prone." -- Hightower, Kelsey; Burns, Brendan; Beda, Joe. Kubernetes: Up and Running: Dive into the Future of Infrastructure (Kindle Locations 183-186). Kindle Edition*

### Usage

All configuration: `./cnti-testsuite configuration`

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

Reads the image reference of every container of the CNF's workloads and reports each one that is not versioned, with the image and the reason. An image is versioned when it is pinned by digest, or by a tag that is present, is not `latest` and names a version, which for the test means it contains a digit (`1.2.3`, `v2`, `6.0.2-debian-11-r0`); untagged images (implicitly `latest`) and moving tags such as `stable` or `main` are not.
Expectation: Every container image is pinned to a version or a digest.

#### Rationale

You should [avoid using the :latest tag](https://kubernetes.io/docs/concepts/containers/images/) when deploying containers in production as it is harder to track which version of the image is running and more difficult to roll back properly.

Sources: [Kubernetes configuration best practices](https://kubernetes.io/docs/concepts/configuration/overview/); [Kubernetes images](https://kubernetes.io/docs/concepts/containers/images/).

#### Remediation

When specifying container images, always specify a tag and ensure to use an immutable tag that maps to a specific version of an application Pod. Remove any usage of the `latest` tag, as it is not guaranteed to be always point to the same version of the image.

#### Usage

`./cnti-testsuite versioned_tag`

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

The hardcoded ip address test will scan all of the CNF's workload resources and check for any static, hardcoded ip addresses being used in the configuration. CIDR notation is allowed and will not cause the test to fail. IP addresses that are justified by application logic are possible to be included in `hardcoded_ip_exceptions` in the [CNF configuration](https://github.com/lfn-cnti/testsuite/blob/main/CNTI_TESTSUITE_YAML_USAGE.md) and will be excluded from violation reports.
Expectation: That no hardcoded IP addresses are found in the Kubernetes workload resources for the CNF unless they are in CIDR format or explicitly listed in `hardcoded_ip_exceptions`.

#### Rationale

Using a hard coded IP in a CNF's configuration designates *how* (imperative) a CNF should achieve a goal, not *what* (declarative) goal the CNF should achieve.

Sources: [The Twelve-Factor App, config](https://12factor.net/config); [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/).

#### Remediation

Review all Helm Charts & Kubernetes Manifest files of the CNF and look for any hardcoded usage of ip addresses. If any are found, you will need to use an operator or some other method to abstract the IP management out of your configuration in order to pass this test.

#### Usage

`./cnti-testsuite hardcoded_ip_addresses_in_k8s_runtime_configuration`

----------

### Secrets used

#### Overview

The secrets used test will scan all the Kubernetes workload resources to see if K8s secrets are being used.
Expectation: The CNF is using K8s secrets for the management of sensitive data.

#### Rationale

If a CNF uses kubernetes K8s secrets instead of unencrypted environment variables or configmaps, there is [less risk of the Secret (and its data) being exposed](https://kubernetes.io/docs/concepts/configuration/secret/) during the workflow of creating, viewing, and editing Pods.

Sources: [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/); [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final); [The Twelve-Factor App, config](https://12factor.net/config).

#### Remediation

Remove any sensitive data stored in configmaps, environment variables and instead utilize K8s Secrets for storing such data.
Alternatively, you can use an operator or some other method to abstract hardcoded sensitive data out of your configuration.
The whole test passes if _any_ workload resource in the cnf uses a (non-exempt) secret. If no workload resources use a (non-exempt) secret, the test is skipped.

#### Usage

`./cnti-testsuite secrets_used`

----------

### Immutable configmap

#### Overview

The immutable configmap test scans the CNF's workload resources for ConfigMaps mounted as volumes or used in container environments and reports each mutable one with the workload and container that uses it. The cluster is first probed with an immutable ConfigMap that must reject a change; a cluster that accepts it does not enforce immutability, and the test is not applicable there.
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

----------

### Kubernetes Alpha APIs

#### Overview

This checks the CNF's rendered manifests for resources declared with alpha API versions and for CustomResourceDefinitions that serve only alpha versions.
Expectation: CNF should not use Kubernetes alpha APIs

#### Rationale

If a CNF uses alpha or undocumented APIs, the CNF is tightly coupled to an unstable platform

Sources: [Kubernetes API deprecation policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/); [Anuket Reference Architecture for Kubernetes (RA2)](https://cntt.readthedocs.io/projects/ra2/en/latest/).

#### Remediation

Make sure your CNFs are not utilizing any Kubernetes alpha APIs. You can learn more about Kubernetes API versioning [here](https://bit.ly/k8s_api).

#### Usage

`./cnti-testsuite alpha_k8s_apis`

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
