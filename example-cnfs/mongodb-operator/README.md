# MongoDB operator

An example of a CNF that an operator deploys. It installs
[MongoDB Controllers for Kubernetes](https://github.com/mongodb/mongodb-kubernetes), MongoDB's
operator, from its Helm chart, then a `MongoDBCommunity` custom resource: a replica set of two data
members and an arbiter. The operator turns the custom resource into the StatefulSets that run
MongoDB. MongoDB is the subscriber database of free5GC, Open5GS and Aether SD-Core, so this is also
the database a 5G core runs on.

The suite finds the operator's StatefulSets through their owner references to the custom resource,
as [K8S_OPERATORS.md](../../docs/K8S_OPERATORS.md) describes, and tests them together with the
operator's own Deployment as one CNF.

## What gets installed

| Deployment | What it is | Priority |
|---|---|---|
| `mongodb-operator` | The `mongodb-kubernetes` chart, version 1.13.0, in the `mongodb` namespace. The operator watches its own namespace. | 1 |
| `replica-set` | [`manifests/mongodb.yaml`](manifests/mongodb.yaml): a `MongoDBCommunity` resource and the Secret with its user's password. | 2 |

The operator requires SCRAM authentication and at least one user, so the manifest carries a
password. It is for testing only; keep a real one out of a repository.

The chart also installs the CRDs of MongoDB's enterprise resources, which this example doesn't use.

## Running it

On a kind cluster with a control plane and two workers:

```bash
./cnti-testsuite setup
./cnti-testsuite cnf_install --cnf-config ./example-cnfs/mongodb-operator/cnti-testsuite.yaml
./cnti-testsuite cert        # or: workload
./cnti-testsuite cnf_uninstall
```

The `MongoDB operator validation` workflow runs both suites every night on a hosted runner.

## Results

With chart 1.13.0, 13 of the 19 essential tests pass, short of the pass mark of 15. The tests that
fail, and what is being done:

| Test | Why it fails | Fix |
|---|---|---|
| `non_root_containers` | The operator and the database pods run as user 2000 with group 0, root. | [mongodb/mongodb-kubernetes#1698](https://github.com/mongodb/mongodb-kubernetes/pull/1698) |
| `readiness` | The operator's Deployment has no readiness probe. | [mongodb/mongodb-kubernetes#1699](https://github.com/mongodb/mongodb-kubernetes/pull/1699) |
| `liveness` | Neither the operator nor the `mongod` containers have a liveness probe. | #1699 and [mongodb/mongodb-kubernetes#1700](https://github.com/mongodb/mongodb-kubernetes/pull/1700) |
| `zombie_handled`, `specialized_init_system` | The operator, `mongod` and the agent run as PID 1 with no init to reap child processes. | Not filed yet |
| `node_drain` | The operator always creates persistent volumes, and kind's volumes are local to one node, so a drained member can't start elsewhere. | None needed on a cluster with network storage |

With the three open pull requests merged, 16 of 19 pass. Until then the nightly accepts a failing
verdict and fails only when the suite errors, so the example keeps exercising operator-deployed
workloads.

The rolling update, downgrade and rollback tests are left out: they change a workload's image
directly, and the operator owns the StatefulSets and reconciles them from the custom resource, so
it can put its own image back. Set the MongoDB version in the custom resource (`spec.version`) to
move the replica set to another release.
