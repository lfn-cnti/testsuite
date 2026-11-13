# sample_disruption_budget_overlap

A CNF with a 2-replica Deployment spread over nodes by a required podAntiAffinity,
selected by two PodDisruptionBudgets that each allow one eviction. The eviction API
refuses pods with more than one budget, so the `disruption_budget` test should fail
against it, naming both budgets.
