# sample_exclusive_cpus_fail

A CNF whose latency-sensitive workload is NOT eligible for exclusive CPUs: the
pod is Guaranteed, but the pinned container (`app`) requests a fractional CPU
(`500m`), which the static CPU manager will not pin. `exclusive_cpus` should fail
and report the container's cpu request.
