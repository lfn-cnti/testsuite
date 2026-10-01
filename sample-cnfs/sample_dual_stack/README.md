# sample_dual_stack

A CNF whose Service declares dual-stack (`spec.ipFamilyPolicy:
PreferDualStack`). The `dual_stack` compatibility test should pass against it.
`PreferDualStack` installs on a single-stack cluster too (it falls back to a
single family but keeps the declared policy), so the fixture is usable in CI.
