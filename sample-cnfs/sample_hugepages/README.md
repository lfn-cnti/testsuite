# sample_hugepages

A CNF whose hugepages `emptyDir` volume (`medium: HugePages-2Mi`) is backed by a
container requesting `hugepages-2Mi`. The `hugepages_volumes` test should pass
against it.

Installed with `--skip-wait-for-install`: the pod requests hugepages, which only
schedule on nodes that pre-allocate them, but the test reads the rendered
manifest, so the pod does not need to become Ready.
