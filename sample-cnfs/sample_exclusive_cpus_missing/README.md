# sample_exclusive_cpus_missing

The `latency_sensitive` config names a workload (`does-not-exist`) that the CNF
does not deploy. The `exclusive_cpus` test cannot measure anything and should
report `skipped` with a remediation, rather than failing.
