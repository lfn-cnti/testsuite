# sample_exclusive_cpus_multi

A CNF with two workloads where only one (`flagged-upf`) is latency-sensitive and
named in `latency_sensitive`. That workload is Guaranteed with a whole-CPU pinned
container; the other (`unflagged-web`) sets no resources and is not checked.
`exclusive_cpus` should pass, showing a multi-workload CNF is judged only on its
named workloads.
