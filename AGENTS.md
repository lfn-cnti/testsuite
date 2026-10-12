# AGENTS.md

Instructions for AI coding agents working in this repository. The guides for people are listed in
the [README](README.md#documentation); start with [CODE_STRUCTURE.md](docs/CODE_STRUCTURE.md) and
[CONTRIBUTING.md](docs/CONTRIBUTING.md). This file adds what they don't say.

## What this is

- One Crystal binary, `cnti-testsuite`, built from `src/cnti-testsuite.cr`. A test is a
  `scored_task` in `src/tasks/workload/` and runs inside `CNFManager::Task.task_runner`.
- Other tools read the suite's output: the GitHub Action, the GitLab CI/CD component and the
  adopters' pipelines. The results file ([schema](docs/cnti-testsuite-results.schema.json)), the
  evidence bundle ([schema](docs/cnti-evidence.schema.json)), the
  [exit codes](docs/USAGE.md#exit-codes) and the CLI options are a contract: a change to any of
  them updates its schema or documentation in the same pull request.

## Build and verify

- Build with `shards install` and `crystal build src/cnti-testsuite.cr`. A type check without code
  generation takes seconds: `crystal build --no-codegen src/cnti-testsuite.cr`.
- Every spec example carries a tag, on the `it` or on an enclosing `describe`. CI fails on an
  untagged example, and every distinct tag becomes its own shard.
- A failed shard may be the runner, not the change: a download that timed out, a port taken on
  a shared host. Read its log before changing code, and rerun it.
- `docs/TEST_DOCUMENTATION.md` is linted by `mdl` with the rules in `doc-lint/`: level-2 headings
  only for the table of contents and the categories, level-3 headings only for tests, each test
  in the table of contents with Overview, Rationale, Remediation and Usage, and every Rationale
  linking at least one external source (by convention on a `Sources:` line).

## How a test behaves

- The result says what the test judged. A failure names the resource, the container and the
  reason (`result.add_impacted_resource(..., reason:)`), and the remediation says how to fix it.
- The verdicts are defined in [USAGE.md](docs/USAGE.md#on-stdout). A test reports N/A, never
  skipped, when its subject is absent from the CNF; skipped means it could not judge.
- A test that cannot fail is a defect. A new test, or a new way to fail, comes with a spec that
  makes it fail, usually with a fixture in `sample-cnfs/`.
- When a tool or a `kubectl` call fails, the finding carries its message, not a generic failure.
  When a workload doesn't become ready, `WorkloadDiagnostics.report` adds its pods, events and
  logs to the details.
- A test that changes the cluster undoes the change before it ends, and registers the undo with
  `RunStop.register` while the change is in force, so a stopped run still cleans up
  (`src/tasks/utils/run_stop.cr`; the chaos tests and `node_drain` do this).

## Pull requests

- Rebase on `main` before review, as CONTRIBUTING asks, and keep a pull request to one change.
  Stage files by name: `cnti/`, built binaries and results files are not committed.
- Versions are pinned on purpose. Renovate moves a pin by the `# renovate:` comment above it
  (`renovate.json`); keep the comment with the pin. The fixtures in `sample-cnfs/` pin their
  charts and images so the specs stay stable.
- A change that alters a verdict on purpose for a CNF in `.github/adopters.yml` adds an
  `expected` entry for it in the same pull request. The adopter canary fails on any other change
  from the adopters' own results.

## Things that look wrong but are not

- `cnti/` is the run's workspace: the installed CNF's configuration and manifests, the results
  and the evidence bundle. It's in `.gitignore`. The tools the suite installs live outside the
  checkout, in `~/.cnti-testsuite` (`CNTI_TESTSUITE_DIR`).
- The maximum score leaves out N/A tests and bonus tests that did not pass (#1465, `points.cr`).
- The pass-criterion task is `cert`, while the badge and the documentation say "essential". The
  task name changes in the next breaking release.
