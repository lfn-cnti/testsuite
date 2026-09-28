# sample_hugepages_unbacked

A CNF with a hugepages `emptyDir` volume (`medium: HugePages-2Mi`) that no
container in the pod backs with a `hugepages-2Mi` request. Kubernetes accepts the
manifest but the pod never starts (it stays in `ContainerCreating` with a
`FailedMount` event). The `hugepages_volumes` test should fail against it.

Installed with `--skip-wait-for-install`: the pod cannot become Ready, but the
test reads the rendered manifest.
