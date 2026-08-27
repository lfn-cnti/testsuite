# sample-sigterm-ignored

A single-process container whose PID 1 (`sleep`) installs no SIGTERM
handler, so as PID 1 it ignores the signal and keeps running. Used to verify
that `sig_term_handled` judges the outcome — the process must terminate within
the pod's grace period — rather than whether strace observed a delivery (#2482).
