# sample_disruption_budget_blocking

A CNF with a 2-replica Deployment whose PodDisruptionBudget sets
`maxUnavailable: 0`, which blocks every drain. The `disruption_budget` test
should fail against it and name the budget.
