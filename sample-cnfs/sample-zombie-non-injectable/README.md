# sample-zombie-non-injectable

A CNF whose container has `readOnlyRootFilesystem: true`, so the `zombie_handled`
probe binaries cannot be copied into it. Used to verify that a failed probe
injection is reported as `skipped` instead of a vacuous `passed` (issue #2474).
