# Where things are

The suite is one Crystal binary, `cnti-testsuite`, built from `src/cnti-testsuite.cr`.

## `src/`

- `tasks/workload/`: the tests, one file per category (`security.cr`, `configuration.cr`,
  `reliability.cr`, `observability.cr`, `microservice.cr`, `state.cr`, `compatibility.cr`).
  A test is a `scored_task`, declares its type (essential, normal, bonus) at the definition,
  and runs inside `CNFManager::Task.task_runner`, which records its result.
- `tasks/suites.cr`, `tasks/cert/`: the suite and category tasks (`all`, `workload`, `cert`,
  each category) and their pass criteria.
- `tasks/setup/`: `setup`, `cnf_install`, `cnf_uninstall`, and the installation of the tools
  the tests need (Kubescape, Kyverno, LitmusChaos, Jaeger, cluster-tools).
- `tasks/utils/cnf_installation/`: parsing `cnti-testsuite.yaml` (config versions, the v1 to v2
  updater) and deploying charts, manifests and operator-managed CNFs.
- `tasks/utils/cnf_manager/`: the task runner, the results file and scoring (`points.cr`),
  the platform record, workload enumeration.
- `tasks/utils/`: the CLI (`cli_*.cr`), the tools' managers (`kubescape.cr`, `kyverno.cr`,
  `litmus_manager.cr`, `jaeger.cr`, ...), diagnostics, the JUnit report, the evidence bundle,
  the stop handling (`run_stop.cr`).
- `tasks/mcp/`: the MCP server (`cnti-testsuite mcp`).
- `modules/`: libraries with no suite logic: `kubectl_client`, `helm`, `cluster_tools`,
  `net_retry`, `docker_client`, and the kernel and network introspection helpers.
- `templates/`: ECR templates rendered at run time (chaos engines, policies).

## Around it

- `spec/`: the specs, run in CI against a kind cluster, sharded by tag
  (`.github/workflows/actions.yml`); `spec/utils/` holds the unit specs that need no cluster.
- `sample-cnfs/`: fixtures the specs install; `example-cnfs/`: the example CNFs users run,
  validated nightly (`example_cnf_validation.yml`).
- `embedded_files/`: files compiled into the binary (values for the collectors, Litmus RBAC).
- `docs/`: the test documentation and the results schema; `doc-lint/`: its lint rules.
- `.github/`: workflows, composite actions, the adopter canary's list (`adopters.yml`).
