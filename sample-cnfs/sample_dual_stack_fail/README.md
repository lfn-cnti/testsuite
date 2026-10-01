# sample_dual_stack_fail

A CNF whose Service does not declare dual-stack (no
`spec.ipFamilyPolicy`, so it defaults to `SingleStack`). The `dual_stack`
compatibility test should fail against it and report the Service as an impacted
resource.
