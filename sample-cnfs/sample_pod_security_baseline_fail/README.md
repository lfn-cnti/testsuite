# sample_pod_security_baseline_fail

A CNF with two Deployments that violate the Pod Security Standards baseline
level: one adds `NET_ADMIN`, one sets AppArmor to `unconfined` through the
`container.apparmor.security.beta.kubernetes.io/*` annotation. The
`pod_security_baseline` test should fail and name both.
