# sample-zombie-readonly-rootfs

A CNF whose container runs with `readOnlyRootFilesystem: true` and busybox `sleep` as
PID 1, which reaps nothing. Used to verify that `zombie_handled` still probes a container
that nothing can be copied into (issue #2542) and reports the unreaped zombie as `failed` -
never `skipped`, and never a vacuous `passed` (issue #2474).
