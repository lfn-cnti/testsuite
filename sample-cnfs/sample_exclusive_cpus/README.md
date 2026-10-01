# sample_exclusive_cpus

A CNF whose latency-sensitive workload is eligible for exclusive CPUs: the pod is
Guaranteed and the pinned container (`app`) requests a whole CPU. A second
container (`sidecar`) requests a fractional CPU but is not named as needing
exclusive CPUs, which is a normal arrangement. `exclusive_cpus` should pass.
