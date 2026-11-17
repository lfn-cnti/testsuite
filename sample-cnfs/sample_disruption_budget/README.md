# sample_disruption_budget

A CNF with a 2-replica Deployment spread over nodes by a required podAntiAffinity,
and a PodDisruptionBudget with `maxUnavailable: 1`. The `disruption_budget` test
should pass against it.
