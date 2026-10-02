# sample_pod_owner_mixed

A CNF with a Deployment and a bare Pod carrying the Deployment's labels. The
`pod_owner` test should fail, naming the bare Pod once, and count 1 of 2 pods.
