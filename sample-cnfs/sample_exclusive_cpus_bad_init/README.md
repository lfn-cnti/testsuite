# sample_exclusive_cpus_bad_init

The pinned container (`app`) is eligible on its own (Guaranteed-shaped, whole CPU
via `1000m`), but the init container (`setup`) requests a fractional CPU with no
limit, so the pod is Burstable, not Guaranteed — and exclusive CPUs are never
assigned. Because QoS is decided by all containers, init included, `exclusive_cpus`
should fail and attribute the finding to the init container, not the main one.
