# CNTI Test Catalog CLI Usage Documentation

### Table of Contents

- [Overview](USAGE.md#overview)
- [Syntax and Usage](USAGE.md#syntax-for-running-any-of-the-tests)
- [Common Examples](USAGE.md#common-example-commands)
- [Logging Options](USAGE.md#logging-options)

### Overview

The CNTI Test Catalog can be run in production mode (using an executable) or in developer mode (using [crystal lang directly](INSTALL.md#source-install)). See the [pseudo code documentation](PSEUDO-CODE.md) for examples of how the internals of WIP tests might work.

### Syntax for running any of the tests

```
# Production mode
./cnf-testsuite <testname>

# Developer mode
crystal src/cnf-testsuite.cr <testname>
```

:star: \*Note: All usage commands in this document will use the production (binary executable) syntax unless otherwise stated.

- :heavy_check_mark: indicates implemented into stable release
- :bulb: indicates Proof of Concept
- :memo: indicates To Do
- :x: indicates WARNINGS\*

### Results Output

- :heavy_check_mark: PASSED indicates it meets best practice, positive points given.
- ⏭ SKIPPED indicates the test was skipped (output should provide a reason), no points given.
- :x: FAILED indicates the test failed, negative points given.

---

### Logging Parameters

- **LOG_LEVEL** environment variable: sets minimal log level to display: error (default); info; debug.
- **LOG_PATH** environment variable: if set - all logs would be appended to the file defined by that variable.

---

### Common Example Commands

#### Building the executable

This is the command to build the binary executable if in developer mode or using the source install method ([requires crystal](INSTALL.md#source-install)):

```
crystal build src/cnf-testsuite.cr
```

#### Validating a cnf-testsuite.yml file:

```
./cnf-testsuite validate_config cnf-config=[PATH_TO]/cnf-testsuite.yml
```

#### Installing a cnf:

```
./cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml
```

##### Skip waiting for resource readiness during installation:
```
./cnf-testsuite cnf_install cnf-config=./cnf-testsuite.yml skip_wait_for_install
```

#### Running all of the platform and workload tests:

```
./cnf-testsuite all cnf-config=<path_to_your_config_file>/cnf-testsuite.yml
```

#### Running all of the tests (including proofs of concepts)

```
./cnf-testsuite all poc cnf-config=<path_to_your_config_file>/cnf-testsuite.yml
```

#### Running all of the workload tests

```
crystal src/cnf-testsuite.cr workload
cnf-config=<path_to_your_config_file>/cnf-testsuite.yml
```

#### Running certification tests

```
./cnf-testsuite cert
./cnf-testsuite cert essential
./cnf-testsuite cert exclude="increase_decrease_capacity single_process_type"
```

#### Running all of the platform or workload tests independently:

##### Run workload only tests:

```
./cnf-testsuite workload
```

##### Run platform only tests (long running):

```
./cnf-testsuite platform
```

#### Get available options and to see all available tests from command line:

```
./cnf-testsuite help
```

#### Clean up the CNTI Test Catalog, the K8s cluster, and upstream projects:

```
./cnf-testsuite uninstall_all
```

---

### Logging Options

#### Update the loglevel from command line:

```
# cmd line
./cnf-testsuite -l debug test
```

#### If in developer mode, make sure to use - - if running from source:

```
crystal src/cnf-testsuite.cr -- -l debug test
```

#### You can also use env var for logging:

```
LOGLEVEL=DEBUG ./cnf-testsuite test
```

:star: Note: When setting log level, the following is the order of precedence:

1. CLI or Command line flag
2. Environment variable
3. CNF-Testsuite [Config file](config.yml)

> Note: Available log levels are: `trace`, `debug`, `info`, `notice`, `warn`, `error` and `fatal`.

#### Environment variables for timeouts:

Timeouts are controlled by these environment variables, set them if default values aren't suitable:
```
CNF_TESTSUITE_GENERIC_OPERATION_TIMEOUT=60
CNF_TESTSUITE_RESOURCE_CREATION_TIMEOUT=120
CNF_TESTSUITE_NODE_READINESS_TIMEOUT=240
CNF_TESTSUITE_POD_READINESS_TIMEOUT=180
CNF_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT=1800
CNF_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION=90
```

#### Running The Linter in Developer Mode

See https://github.com/crystal-ameba/ameba for more details. Follow the [INSTALL](INSTALL.md) guide starting at the [Source Install](INSTALL.md#source-install) for more details running cnf-testsuite in developer mode.

```
shards install # only for first install
crystal bin/ameba.cr
```

---
# Compatibility, Installability, and Upgradability Tests

##### To run all of the compatibility tests

```
./cnf-testsuite compatibility
```

## [Increase decrease capacity:](https://github.com/cnti-testcatalog/testsuite/blob/refactor_usage_doc%231371/docs/LIST_OF_TESTS.md#increase-decrease-capacity)
##### To run both increase and decrease tests, you can use the alias command that calls them both:
```
./cnf-testsuite increase_decrease_capacity
```

<b>Remediation for failing this test:</b>

Check out the kubectl docs for how to [manually scale your cnf.](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#scaling-resources)

Also here is some info about [things that could cause failures.](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#failed-deployment)

</b>



## [Helm chart published](docs/LIST_OF_TESTS.md#helm-chart-published)

##### To run the Helm chart published test, you can use the following command:
```
./cnf-testsuite helm_chart_published
```

<b>Remediation for failing this test:</b>

Make sure your CNF helm charts are published in a Helm Repository.

</b>



## [Helm chart is valid](docs/LIST_OF_TESTS.md#helm-chart-valid)

##### To run the Helm chart vaild test, you can use the following command:
```
./cnf-testsuite helm_chart_valid
```

<b>Remediation for failing this test:</b> 

Make sure your helm charts pass lint tests.

</b>



## [Helm deploy](docs/LIST_OF_TESTS.md#helm-deploy)

##### To run the Helm deploy test, you can use the following command:
```
./cnf-testsuite helm_deploy
```

<b>Remediation for failing this test:</b> 

Make sure your helm charts are valid and can be deployed to clusters.

</b>



## [Rollback](docs/LIST_OF_TESTS.md#rollback)

##### To run the Rollback test, you can use the following command:
```
./cnf-testsuite rollback
```
<b>Remediation for failing this test:</b> 

Ensure that you can upgrade your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command, then rollback the upgrade using the [Kubectl Rollout Undo](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout) command.

</b>


### [Rolling update](docs/LIST_OF_TESTS.md#rolling-update)

##### To run the Rolling update test, you can use the following command:
```
./cnf-testsuite rolling_update
```

<b>Remediation for failing this test:</b> 

Ensure that you can successfuly perform a rolling upgrade of your CNF using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

</b>



### [Rolling version change](docs/LIST_OF_TESTS.md#rolling-version-change)

##### To run the Rolling version change test, you can use the following command:
```
./cnf-testsuite rolling_version_change
```

<b>Remediation for failing this test:</b> 

Ensure that you can successfuly rollback the software version of your CNF by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

</b>


### [Rolling downgrade](docs/LIST_OF_TESTS.md#rolling-downgrade)

##### To run the Rolling downgrade test, you can use the following command:
```
./cnf-testsuite rolling_downgrade
```

<b>Remediation for failing this test:</b> 

Ensure that you can successfuly change the software version of your CNF back to an older version by using the [Kubectl Set Image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-image-em-) command.

</b>


## [CNI compatible](docs/LIST_OF_TESTS.md#cni-compatible)

##### To run the CNI compatible test, you can use the following command:
```
./cnf-testsuite cni_compatible
```

<b>Remediation for failing this test:</b> 

Ensure that your CNF is compatible with Calico, Cilium and other available CNIs.

</b>



## [Kubernetes Alpha APIs](docs/LIST_OF_TESTS.md#kubernetes-alpha-apis---proof-of-concept)

##### To run the Kubernetes Alpha APIs test, you can use the following command:
```
./cnf-testsuite alpha_k8s_apis
```

<b>Remediation for failing this test:</b> 

Make sure your CNFs are not utilizing any Kubernetes alpha APIs. You can learn more about Kubernetes API versioning [here](https://bit.ly/k8s_api).

</b>



<details> <summary>Details for Compatibility, Installability and Upgradability Tests To Do's</summary>
<p>

#### :memo: (To Do) To check of the CNF's CNI plugin accepts valid calls from the [CNI specification](https://github.com/containernetworking/cni/blob/master/SPEC.md)

```
crystal src/cnf-testsuite.cr cni_spec
```

#### :memo: (To Do) To check for the use of beta K8s API endpoints

```
crystal src/cnf-testsuite.cr api_snoop_beta
```

#### :memo: (To Do) To check for the use of generally available (GA) K8s API endpoints

```
crystal src/cnf-testsuite.cr api_snoop_general_apis
```

#### :memo: (To Do) To test small scale autoscaling

```
crystal src/cnf-testsuite.cr small_autoscaling
```

#### :memo: (To Do) To test [large scale autoscaling](https://github.com/cncf/cnf-testbed)

```
crystal src/cnf-testsuite.cr large_autoscaling
```

#### :memo: (To Do) To test if the CNF responds to [network](https://github.com/alexei-led/pumba) [chaos](https://github.com/worstcase/blockade)

```
crystal src/cnf-testsuite.cr network_chaos
```

#### :memo: (To Do) To test if the CNF control layer uses [external retry logic](https://github.com/envoyproxy/envoy)

```
crystal src/cnf-testsuite.cr external_retry
```
    
#### :memo: (To Do) To test small scale autoscaling

```
crystal src/cnf-testsuite.cr small_autoscaling
```

#### :memo: (To Do) To test [large scale autoscaling](https://github.com/cncf/cnf-testbed)

```
crystal src/cnf-testsuite.cr large_autoscaling
```

#### :memo: (To Do) To test if the CNF responds to [network](https://github.com/alexei-led/pumba) [chaos](https://github.com/worstcase/blockade)

```
crystal src/cnf-testsuite.cr network_chaos
```

#### :memo: (To Do) To test if the CNF control layer uses [external retry logic](https://github.com/envoyproxy/envoy)

```
crystal src/cnf-testsuite.cr external_retry
```


</p>
</details>


# Microservice Tests

##### To run all of the microservice tests

```
./cnf-testsuite microservice
```

## [Reasonable Image Size](docs/LIST_OF_TESTS.md#reasonable-image-size)

##### To run the Reasonable image size, you can use the following command:
```
./cnf-testsuite reasonable_image_size
```

<b>Remediation for failing this test:</b> 

Enure your CNFs image size is under 5GB.

</b>



## [Reasonable startup time](docs/LIST_OF_TESTS.md#reasonable-startup-time)

##### To run the Reasonable startup time test, you can use the following command:

```
./cnf-testsuite reasonable_startup_time
```

<b>Remediation for failing this test:</b> 

Ensure that your CNF gets into a running state within 30 seconds.

</b>


## [Single process type in one container](docs/LIST_OF_TESTS.md#single-process-type-in-one-container)

##### To run the Single process type test, you can use the following command:

```
./cnf-testsuite single_process_type
```

<b>Remediation for failing this test:</b> 

Ensure that there is only one process type within a container. This does not count against child processes, e.g. nginx or httpd could be a parent process with 10 child processes and pass this test, but if both nginx and httpd were running, this test would fail.

</b>




## [Service discovery](docs/LIST_OF_TESTS.md#service-discovery)

##### To run the Service discovery test, you can use the following command:

```
./cnf-testsuite service_discovery
```

<b>Remediation for failing this test:</b> 
  
Make sure the CNF exposes any of its containers as a Kubernetes Service. You can learn more about Kubernetes Service [here](https://kubernetes.io/docs/concepts/services-networking/service/).
  
</b>



## [Shared database](docs/LIST_OF_TESTS.md#shared-database)

##### To run the Shared database test, you can use the following command:


```
./cnf-testsuite shared_database 
```

<b>Remediation for failing this test:</b> 

Make sure that your CNFs containers are not sharing the same [database](https://martinfowler.com/bliki/IntegrationDatabase.html).
</b>

## [Specialized Init System](docs/LIST_OF_TESTS.md#specialized-init-system)

##### To run the Specialized Init System test, you can use the following command:

```
./cnf-testsuite specialized_init_system
```

<b>Remediation for failing this test:</b> 

Use init systems that are purpose-built for containers like tini, dumb-init, s6-overlay.

## [Sigterm Handled](docs/LIST_OF_TESTS.md#sig-term-handled)

##### To run the Sigterm Handled test, you can use the following command:

```
./cnf-testsuite sig_term_handled
```

<b>Remediation for failing this test:</b>

Make the PID 1 container process to handle SIGTERM; enable process namespace sharing in Kubernetes or use specialized Init system.
</b>

## [Zombie Handled](docs/LIST_OF_TESTS.md#zombie-handled)

##### To run the Zombie Handled test, you can use the following command:

```
./cnf-testsuite zombie_handled
```

<b>Remediation for failing this test:</b>

Make the PID 1 container process to handle/reap zombie processes; enable process namespace sharing in Kubernetes or use specialized Init system.
</b>


# State Tests

##### To run all of the state tests:

```
./cnf-testsuite state
```

## [Node drain](docs/LIST_OF_TESTS.md#node-drain)

##### To run the Node drain test, you can use the following command:

```
./cnf-testsuite node_drain
```

Please note, that this test requires a cluster with atleast two schedulable nodes.

<b>Remediation for failing this test</b> 
Ensure that your CNF can be successfully rescheduled when a node fails or is [drained](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
</b>




## [Volume hostpath not found](docs/LIST_OF_TESTS.md#volume-hostpath-not-found)

##### To run the Volume hostpath not found test, you can use the following command:

```
./cnf-testsuite volume_hostpath_not_found
```

<b>Remediation for failing this test:</b> 
Ensure that none of the containers in your CNFs are using ["hostPath"] to mount volumes.
</b>



## [No local volume configuration](docs/LIST_OF_TESTS.md#no-local-volume-configuration)

##### To run the No local volume configuration test, you can use the following command:

```
./cnf-testsuite no_local_volume_configuration
```

<b>Remediation for failing this test:</b>
Ensure that your CNF isn't using any persistent volumes that use a ["local"] mount point.
</b>



## [Elastic volumes](docs/LIST_OF_TESTS.md#elastic-volumes)

##### To run the Elastic volume test, you can use the following command:

```
./cnf-testsuite elastic_volume
```

<b>Remediation for failing this test:</b> 
Setup and use elastic persistent volumes instead of local storage.
</b>



## [Database persistence](docs/LIST_OF_TESTS.md#database-persistence)

##### To run the Database persistence test, you can use the following command:

```
./cnf-testsuite database_persistence 
```

<b>Remediation for failing this test:</b> 
Select a database configuration that uses statefulsets and elastic storage volumes.
</b>


# Reliability, Resilience and Availability

##### To run all of the resilience tests
```
./cnf-testsuite resilience
```

## [CNF network latency](docs/LIST_OF_TESTS.md#cnf-under-network-latency)

##### To run the CNF network latency test, you can use the following command:

```
./cnf-testsuite pod_network_latency
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF doesn't stall or get into a corrupted state when network degradation occurs.
A mitigation stagagy (in this case keep the timeout i.e., access latency low) could be via some middleware that can switch traffic based on some SLOs parameters.
</b>

## [CNF disk fill](docs/LIST_OF_TESTS.md#cnf-with-host-disk-fill)

##### To run the CNF disk fill test, you can use the following command:

```
./cnf-testsuite disk_fill
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is resilient and doesn't stall when heavy IO causes a degradation in storage resource availability. 
</b>


## [Pod delete](docs/LIST_OF_TESTS.md#pod-delete)

##### To run the CNF Pod delete test, you can use the following command:
```
./cnf-testsuite pod_delete
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is resilient and doesn't fail on a forced/graceful pod failure on specific or random replicas of an application. 
</b>


## [Memory hog](docs/LIST_OF_TESTS.md#memory-hog)

##### To run the CNF Pod delete test, you can use the following command:
```
./cnf-testsuite pod_memory_hog
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is resilient to heavy memory usage and can maintain some level of availability. 
</b>


## [IO Stress](docs/LIST_OF_TESTS.md#io-stress)

##### To run the IO Stress test, you can use the following command:
```
./cnf-testsuite pod_io_stress
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is resilient to continuous and heavy disk IO load and can maintain some level of availability
</b>

## [Network corruption](docs/LIST_OF_TESTS.md#network-corruption)

##### To run the Network corruption test, you can use the following command:
```
./cnf-testsuite pod_network_corruption
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is resilient to a lossy/flaky network and can maintain a level of availability.
</b>



## [Network duplication](docs/LIST_OF_TESTS.md#network-duplication)

##### To run the Network duplication test, you can use the following command:
```
./cnf-testsuite pod_network_duplication
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is resilient to erroneously duplicated packets and can maintain a level of availability.
</b>


## [Pod DNS errors](docs/LIST_OF_TESTS.md#pod-dns-errors)

##### To run the Pod DNS error test, you can use the following command:
```
./cnf-testsuite pod_dns_error
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is resilient to DNS resolution failures can maintain a level of availability.

</b>


## [Helm chart liveness entry](docs/LIST_OF_TESTS.md#helm-chart-liveness-entry)

##### To run the Helm chart liveness entry test, you can use the following command:
  
```
./cnf-testsuite liveness
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF has a [Liveness Probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) configured.
</b>



## [Helm chart readiness entry](docs/LIST_OF_TESTS.md#helm-chart-readiness-entry)

##### To run the Helm chart readiness entry test, you can use the following command:

```
./cnf-testsuite readiness
```
<b>Remediation for failing this test:</b> 
Ensure that your CNF has a [Readiness Probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) configured.
</b>


# Observability and Diagnostic Tests

##### To run all observability tests, you can use the following command:

```
./cnf-testsuite observability
```

## [Use stdout/stderr for logs](docs/LIST_OF_TESTS.md#use-stdoutstderr-for-logs)

##### To run the stdout/stderr logging test, you can use the following command:

```
./cnf-testsuite log_output
``` 

<b>Remediation for failing this test:</b> 
Make sure applications and CNF's are sending log output to STDOUT and or STDERR.
</b>


## [Prometheus installed](docs/LIST_OF_TESTS.md#prometheus-installed)

##### To run the Prometheus installed test, you can use the following command:
```
./cnf-testsuite prometheus_traffic 
``` 

<b>Remediation for failing this test:</b> 
Install and configure Prometheus for your CNF.
</b>



## [Routed logs](docs/LIST_OF_TESTS.md#routed-logs)

##### To run the routed logs test, you can use the following command:
```
./cnf-testsuite routed_logs
```

<b>Remediation for failing this test:</b> 
Install and configure fluentd or fluentbit to collect data and logs. See more at [fluentd.org](https://bit.ly/fluentd) for fluentd or [fluentbit.io](https://fluentbit.io/) for fluentbit.
</b>


## [OpenMetrics compatible](docs/LIST_OF_TESTS.md#openmetrics-compatible)

##### To run the OpenMetrics compatible test, you can use the following command:
```
./cnf-testsuite open_metrics
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is publishing OpenMetrics compatible metrics.
</b>



## [Jaeger tracing](docs/LIST_OF_TESTS.md#jaeger-tracing)

##### To run the Jaeger tracing test, you can use the following command:
```
./cnf-testsuite tracing
```

<b>Remediation for failing this test:</b> 
Ensure that your CNF is both using & publishing traces to Jaeger.
</b>



# Security Tests

##### To run all of the security tests, you can use the following command:

```
./cnf-testsuite security
```

## [Container socket mounts](docs/LIST_OF_TESTS.md#container-socket-mounts)

##### To run the Container socket mount test, you can use the following command:

```
./cnf-testsuite container_sock_mounts
```

<b>Remediation for failing this test:</b> 
Make sure your CNF doesn't mount `/var/run/docker.sock`, `/var/run/containerd.sock` or `/var/run/crio.sock` on any containers.
</b>


## [External IPs](docs/LIST_OF_TESTS.md#external-ips)

##### To run the External IPs test, you can use the following command:
```
./cnf-testsuite external_ips
```

<b>Remediation for failing this test:</b> 
Make sure to not define external IPs in your kubernetes service configuration
</b>

## [Privileged containers](docs/LIST_OF_TESTS.md#privileged-containers)

##### To run the Privilege container test, you can use the following command:

```
./cnf-testsuite privileged_containers
```

    
<b>Remediation for failing this test:</b> 

Remove privileged capabilities by setting the securityContext.privileged to false. If you must deploy a Pod as privileged, add other restriction to it, such as network policy, Seccomp etc and still remove all unnecessary capabilities.
        
</b>


## [Privilege escalation](docs/LIST_OF_TESTS.md#privilege-escalation)

##### To run the Privilege escalation test, you can use the following command:
```
./cnf-testsuite privilege_escalation
```

<b>Remediation for failing this test:</b> 
If your application does not need it, make sure the allowPrivilegeEscalation field of the securityContext is set to false. See more at [ARMO-C0016](https://bit.ly/C0016_privilege_escalation)

</b>


## [Symlink file system](docs/LIST_OF_TESTS.md#symlink-file-system)

##### To run the Symlink file test, you can use the following command:
```
./cnf-testsuite symlink_file_system
```

<b>Remediation for failing this test:</b> 
To mitigate this vulnerability without upgrading kubelet, you can disable the VolumeSubpath feature gate on kubelet and kube-apiserver, or remove any existing Pods using subPath or subPathExpr feature.
</b>


## [Sysctls](docs/LIST_OF_TESTS.md#sysctls)

##### To run the Sysctls test, you can use the following command:
```
./cnf-testsuite sysctls
```

<b>Remediation for failing this test:</b> 
The spec.securityContext.sysctls field must be unset or not use. 
</b>


## [Application credentials](docs/LIST_OF_TESTS.md#application-credentials)

##### To run the Application credentials test, you can use the following command:
```
./cnf-testsuite application_credentials
```

<b>Remediation for failing this test:</b> 
Use Kubernetes secrets or Key Management Systems to store credentials.
</b>


## [Host network](docs/LIST_OF_TESTS.md#host-network)

##### To run the Host network credentials test, you can use the following command:
```
./cnf-testsuite host_network
``` 

<b>Remediation for failing this test:</b> 
Only connect PODs to the hostNetwork when it is necessary. If not, set the hostNetwork field of the pod spec to false, or completely remove it (false is the default). Allow only those PODs that must have access to host network by design.
</b>




## [Service account mapping](docs/LIST_OF_TESTS.md#service-account-mapping)

##### To run the Service account mapping test, you can use the following command:
```
./cnf-testsuite service_account_mapping
```

<b>Remediation for failing this test:</b> 
Disable automatic mounting of service account tokens to PODs either at the service account level or at the individual POD level, by specifying the automountServiceAccountToken: false. Note that POD level takes precedence.
</b>


## [Ingress and Egress blocked](docs/LIST_OF_TESTS.md#ingress-and-egress-blocked)

##### To run the Ingress and Egress test, you can use the following command:
```
./cnf-testsuite ingress_egress_blocked
```

<b>Remediation for failing this test: </b> 

By default, you should disable or restrict Ingress and Egress traffic on all pods.
</b>


## [Insecure capabilities](docs/LIST_OF_TESTS.md#insecure-capabilities)

##### To run the Insecure capabilities test, you can use the following command:

```
./cnf-testsuite insecure_capabilities
```


<b>Remediation for failing this test:</b> 

Remove all insecure capabilities which aren’t necessary for the container.

</b>


## [Non Root containers](docs/LIST_OF_TESTS.md#non-root-containers)

##### To run the Non-root containers test, you can use the following command:

```
./cnf-testsuite non_root_containers
```

<b>Remediation for failing this test:</b> 

If your application does not need root privileges, make sure to define the runAsUser and runAsGroup under the PodSecurityContext to use user ID 1000 or higher, do not turn on allowPrivlegeEscalation bit and runAsNonRoot is true.
        
</b>

## [Host PID/IPC privileges](docs/LIST_OF_TESTS.md#host-pidipc-privileges)

##### To run the Host PID/IPC test, you can use the following command:

```
./cnf-testsuite host_pid_ipc_privileges
```

<b>Remediation for failing this test:</b> 

Apply least privilege principle and remove hostPID and hostIPC from the yaml configuration privileges unless they are absolutely necessary.
 
</b>


## [Linux hardening](docs/LIST_OF_TESTS.md#linux-hardening)
    
##### To run the Linux hardening test, you can use the following command:
```
./cnf-testsuite linux_hardening
```

<b>Remediation for failing this test:</b> 

Use AppArmor, Seccomp, SELinux and Linux Capabilities mechanisms to restrict containers abilities to utilize unwanted privileges.

</b>



## [CPU limits](docs/LIST_OF_TESTS.md#cpu-limits)

##### To run the CPU limits test, you can use the following command:
```
./cnf-testsuite cpu_limits
```

<b>Remediation for failing this test:</b> 

Define LimitRange and ResourceQuota policies to limit CPU usage for namespaces or in the deployment/POD yamls.
        
</b>


## [Memory limits](docs/LIST_OF_TESTS.md#memory-limits)

##### To run the memory limits test, you can use the following command:
```
./cnf-testsuite memory_limits
```

<b>Remediation for failing this test:</b> 

Define LimitRange and ResourceQuota policies to limit memory usage for namespaces or in the deployment/POD yamls.
        
</b>


## [Immutable File Systems](docs/LIST_OF_TESTS.md#immutable-file-systems)

##### To run the Immutable File Systems test, you can use the following command:
```
./cnf-testsuite immutable_file_systems
```

<b>Remediation for failing this test:</b>

Set the filesystem of the container to read-only when possible. If the containers application needs to write into the filesystem, it is possible to mount secondary filesystems for specific directories where application require write access.
        
</b>


## [HostPath Mounts](docs/LIST_OF_TESTS.md#hostpath-mounts)

##### To run the HostPath Mounts test, you can use the following command:
```
./cnf-testsuite hostpath_mounts
```

<b>Remediation for failing this test:</b> 

Refrain from using a hostPath mount.
        
</b>


## [SELinux options](docs/LIST_OF_TESTS.md#selinux-options)

##### To run the SELinux options test, you can use the following command:
```
./cnf-testsuite selinux_options
```

<b>Remediation for failing this test:</b>
Ensure the following guidelines are followed for any cluster resource that allow SELinux options.
  <ul>
    <li>
    If the SELinux option `type` is set, it should only be one of the allowed values: `container_t`, `container_init_t`, or `container_kvm_t`.
    </li>
    <li>
    SELinux options `user` or `role` should not be set.
    </li>
  </ul>
  
</b>

<details> <summary>Details for Security Tests To Do's</summary>
<p>

#### :memo: (To Do) To check if there are any [shells running in the container](https://github.com/open-policy-agent/gatekeeper)

```
crystal src/cnf-testsuite.cr shells
```

#### :memo: (To Do) To check if there are any [protected directories](https://github.com/open-policy-agent/gatekeeper) or files that are accessed from within the container

```
crystal src/cnf-testsuite.cr protected_access
```

</p>
</details>

# Configuration Tests

##### To run all Configuration tests, you can use the following command:

```
./cnf-testsuite configuration_lifecycle
```

## [Default namespaces](docs/LIST_OF_TESTS.md#default-namespaces)

##### To run the Default namespace test, you can use the following command:
```
./cnf-testsuite default_namespace
```

<b>Remediation for failing this test:</b> 

Ensure that your CNF is configured to use a Namespace and is not using the default namespace. 

</b>



## [Latest tag](docs/LIST_OF_TESTS.md#latest-tag)

##### To run the Latest tag test, you can use the following command:
```
./cnf-testsuite latest_tag
```

<b>Remediation for failing this test:</b>

When specifying container images, always specify a tag and ensure to use an immutable tag that maps to a specific version of an application Pod. Remove any usage of the `latest` tag, as it is not guaranteed to be always point to the same version of the image.

</b>


## [Require labels](docs/LIST_OF_TESTS.md#require-labels)

##### To run the require labels test, you can use the following command:
```
./cnf-testsuite require_labels
```

<b>Remediation for failing this test:</b> 

Make sure to define `app.kubernetes.io/name` label under metadata for your CNF.

</b>


## [Versioned tag](docs/LIST_OF_TESTS.md#versioned-tag) 

##### To run the versioned tag test, you can use the following command:
```
./cnf-testsuite versioned_tag
```

<b>Remediation for failing this test:</b>

When specifying container images, always specify a tag and ensure to use an immutable tag that maps to a specific version of an application Pod. Remove any usage of the `latest` tag, as it is not guaranteed to be always point to the same version of the image.

</b>


## [nodePort not used](docs/LIST_OF_TESTS.md#nodeport-not-used)

##### To run the nodePort not used test, you can use the following command:
```
./cnf-testsuite nodeport_not_used
```

<b>Remediation for failing this test:</b> 

Review all Helm Charts & Kubernetes Manifest files for the CNF and remove all occurrences of the nostPort field in you configuration. Alternatively, configure a service or use another mechanism for exposing your container.

</b>


## [hostPort not used](docs/LIST_OF_TESTS.md#hostport-not-used)

##### To run the hodePort not used test, you can use the following command:

```
./cnf-testsuite hostport_not_used
```

<b>Remediation for failing this test:</b> 

Review all Helm Charts & Kubernetes Manifest files for the CNF and remove all occurrences of the hostPort field in you configuration. Alternatively, configure a service or use another mechanism for exposing your container.
</b>




## [Hardcoded IP addresses in K8s runtime configuration](docs/LIST_OF_TESTS.md#Hardcoded-ip-addresses-in-k8s-runtime-configuration)

##### To run the Hardcoded IP addresses test, you can use the following command:

```
./cnf-testsuite hardcoded_ip_addresses_in_k8s_runtime_configuration
```

<b>Remediation for failing this test:</b> 

Review all Helm Charts & Kubernetes Manifest files of the CNF and look for any hardcoded usage of ip addresses. If any are found, you will need to use an operator or some other method to abstract the IP management out of your configuration in order to pass this test.   
</b>



## [Secrets used](docs/LIST_OF_TESTS.md#secrets-used)

##### To run the Secrets used test, you can use the following command:
```
./cnf-testsuite secrets_used
```

<b>Rules for the test:</b> The whole test passes if _any_ workload resource in the cnf uses a (non-exempt) secret. If no workload resources use a (non-exempt) secret, the test is skipped.

<b>Remediation for failing this test:</b> 

Remove any sensitive data stored in configmaps, environment variables and instead utilize K8s Secrets for storing such data.  Alternatively, you can use an operator or some other method to abstract hardcoded sensitive data out of your configuration.   
</b>



## [Immutable configmaps](docs/LIST_OF_TESTS.md#immutable-configmap)

##### To run the immutable configmap test, you can use the following command:
```
./cnf-testsuite immutable_configmap
```

<b>Remediation for failing this test:</b> 
Use immutable configmaps for any non-mutable configuration data.
</b>

# 5g Tests

##### To run all 5g tests, you can use the following command:

```
./cnf-testsuite 5g
```

## [smf_upf_core_validator](docs/LIST_OF_TESTS.md#smf_upf_core_validator)

##### To run the 5g core_validator test, you can use the following command:

```
./cnf-testsuite smf_upf_core_validator
```
## [suci_enabled](docs/LIST_OF_TESTS.md#suci_enabled)
##### To run the 5g suci_enabled test, you can use the following command:

```
./cnf-testsuite suci_enabled
```

# RAN Tests

##### To run all RAN tests, you can use the following command:

```
./cnf-testsuite ran
```

## [oran_e2_connection](docs/LIST_OF_TESTS.md#oran_e2_connection)

##### To run the oran e2 connection test, you can use the following command:

```
./cnf-testsuite oran_e2_connection
```



# Platform Tests

##### To run all Platform tests, you can use the following command:

```
./cnf-testsuite platform
```

## [K8s Conformance](docs/LIST_OF_TESTS.md#k8s-conformance)

##### To run the K8s Conformance test, you can use the following command:

```
./cnf-testsuite k8s_conformance
```

<b>Remediation for failing this test:</b> 
Check that [Sonobuoy](https://github.com/vmware-tanzu/sonobuoy) can be successfully run and passes without failure on your platform. Any failures found by Sonobuoy will provide debug and remediation steps required to get your K8s cluster into a conformant state.
</b>


## [ClusterAPI enabled](docs/LIST_OF_TESTS.md#clusterapi-enabled)

##### To run the ClusterAPI enabled test, you can use the following command:

```
./cnf-testsuite clusterapi_enabled
```

<b>Remediation for failing this test:</b> 
Enable ClusterAPI and start using it to manage the provisioning and lifecycle of your Kubernetes clusters.
</b>


##### To run all platform harware and scheduling tests, you can use the following command:
```
./cnf-testsuite  platform:hardware_and_scheduling
```

## [OCI Compliant](docs/LIST_OF_TESTS.md#oci-compliant)

##### To run the OCI Compliant test, you can use the following command:

```
./cnf-testsuite platform:oci_compliant
```
<b>Remediation for failing this test:</b> 

Check if your Kuberentes Platform is using an [OCI Compliant Runtime](https://opencontainers.org/). If you platform is not using an OCI Compliant Runtime, you'll need to switch to a new runtime that is OCI Compliant in order to pass this test.

</b>


##### (PoC) To run All platform resilience tests, you can use the following command:

```
./cnf-testsuite platform:resilience poc
```

## [Worker reboot recovery](docs/LIST_OF_TESTS.md#poc-worker-reboot-recovery)

##### To run the Worker reboot recovery test, you can use the following command:

```
./cnf-testsuite platform:worker_reboot_recovery poc destructive
```
<b>Remediation for failing this test:</b> 

Reboot a worker node in your Kubernetes cluster verify that the node can recover and re-join the cluster in a schedulable state. Workloads should also be rescheduled to the node once it's back online. 
</b>



##### :heavy_check_mark: Run All platform security tests

```
./cnf-testsuite platform:security 
```
## [Cluster admin](docs/LIST_OF_TESTS.md#cluster-admin)
##### To run the Cluster admin test, you can use the following command:

```
./cnf-testsuite platform:cluster_admin
```

<b>Remediation for failing this test:</b> 
You should apply least privilege principle. Make sure cluster admin permissions are granted only when it is absolutely necessary. Don't use subjects with high privileged permissions for daily operations.

See more at [ARMO-C0035](https://bit.ly/C0035_cluster_admin)

</b>


## [Control plane hardening](docs/LIST_OF_TESTS.md#control-plane-hardening)

##### To run the Control plane hardening test, you can use the following command:

```
./cnf-testsuite platform:control_plane_hardening
```

<b>Remediation for failing this test:</b> 

Set the insecure-port flag of the API server to zero.

See more at [ARMO-C0005](https://bit.ly/C0005_Control_Plane)

</b>

```
./cnf-testsuite platform:control_plane_hardening
```


## [Tiller images](docs/LIST_OF_TESTS.md#tiller-images)

##### To run the Tiller images test, you can use the following command:
```
./cnf-testsuite platform:helm_tiller
```

<b>Remediation for failing this test:</b> 
Switch to using Helm v3+ and make sure not to pull any images with name tiller in them
</b>


## [Kubescape secret/etcd](docs/LIST_OF_TESTS.md#kubescape-secret-etcd)

##### To run the Kubescape secret/etcd test, you can use the following command:
```
./cnf-testsuite platform:kubescape_secret_etc
```

<b>Remediation for failing this test: </b>

Check version of ETCDCTL in etcd pod, it should be v3.+

</b>