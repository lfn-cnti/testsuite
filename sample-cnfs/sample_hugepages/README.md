# sample_hugepages

A CNF with a well-formed hugepages consumer, used by the `well_formed_hugepages`
workload test. The container requests `hugepages-2Mi` with matching requests and
limits, also sets a memory request, and mounts an `emptyDir` volume whose medium
(`HugePages-2Mi`) matches the requested page size. `well_formed_hugepages` should
pass against it.

Installed with `--skip-wait-for-install`: the pod requests hugepages, which only
schedule on nodes that pre-allocate them, but the static test reads the Deployment
spec, so the pod does not need to become Ready.
