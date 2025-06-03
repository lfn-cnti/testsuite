## Contributing Guidelines

Welcome! We gladly accept contributions on new tests, example CNFs, updates to documentation, enhancements, bug reports and more.

The CNTI Test Suite is [Apache 2.0 licensed](LICENSE) and accepts contributions via GitHub pull requests. Please read the following guidelines carefully to make it easier to get your contribution accepted.

## Support Channels:

Support channels include:

- [Issues](../../issues)
- Join the conversation on [LFN Tech's Slack](https://lfntech.slack.com/) [#cnti](https://lfntech.slack.com/archives/C06HQGWK4NL) channel

Before starting work on a major feature, please reach out to us via [GitHub Issues](../../issues) or Slack. We will make sure no one else is already working on it and ask you to open a [GitHub issue](../../issues/new/choose).

- Small patches and bug fixes don't need prior communication.

## Issues

GitHub Issues are used as the primary method for tracking items for the CNTI Test Suite. Please self-assign an issue to yourself when you start to work on it so we don't duplicate work :)

- [Issues](../../issues)
  - [Good first issues](https://github.com/lfn-cnti/testsuite/labels/good%20first%20issue)
  - [Contributions welcome](https://github.com/lfn-cnti/testsuite/labels/contributions-welcome)

### Issue Templates

**1. New Features:**
To request an enhancement, please create a new issue using the [**Feature Request**](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=enhancement&template=feature-request.md&title=%5BFeature%5D) Template

**2. Report Bugs:**
To report a bug, please create a new issue using the [**Bug Report**](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=bug&template=bug-report.md&title=%5BBUG%5D) Template. Check out [How to Report Bugs Effectively](https://www.chiark.greenend.org.uk/~sgtatham/bugs.html.).

>NOTE: To help with debugging, you can enable higher logging level output via the command line or ENV variable. Available log levels are: `trace`, `debug`, `info`, `notice`, `warn`, `error` and `fatal`.

```
# cmd line
./cnf-testsuite -l debug test

# make sure to use -- if running from source
crystal src/cnf-testsuite.cr -- -l debug test

# env var
LOGLEVEL=DEBUG ./cnf-testsuite test
```

Check [usage documentation](USAGE.md) for more info about invoking commands and loggin

**3. New CNTI Test Suite Tests:**

- To request a new workload test, please create a new issue using the [**New Workload Test**](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=workload&template=new-workload-test.md&title=%5BWorkload%5D) Template
- To request a new platform test, please create a new issue using the [**New Platform Test**](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=platform&template=new-platform-test.md&title=%5BPlatform%5D) Template

**4. New CNF Example:**
To suggest a new CNF, please create a GitHub issue using the [New Example CNF template](https://github.com/lfn-cnti/testsuite/issues/new?assignees=&labels=example+CNF&template=new-example-cnf.md&title=%5BCNF%5D).

To install the CNTI Test Suite and run a CNF, follow instructions at:

- [CNF Developer Install and Usage Guide](SOURCE_INSTALL.md)

## Coding Style:

The test framework and tests (using upstream tools) are written in the human readable, compiled language, Crystal. Common capabilities like dependencies between tests and categories are supported.

- See https://crystal-lang.org/reference/conventions/coding_style.html

## Contribution Flow

Outline of what a contributor's workflow looks like:

1. Fork it (https://github.com/lfn-cnti/testsuite/fork)
1. Create a branch from where you want to base your work (usually main). Example `git checkout -b my-new-feature)`
1. Read the install for build and test instructions at [INSTALL.md](INSTALL.md).
1. Make your changes and arrange them in readable commits.
1. Commit your changes (Ex. `git commit -am 'Add some feature'``)
   - Make sure your commit messages are in the proper format (see below).
1. Push to the branch (Ex. `git push origin my-new-feature`)
1. Make sure branch is up to date with upstream base branch (eg. `main`)
1. Make sure all tests pass, and add any new tests as appropriate.
1. Create a new Pull Request (PR)

## Submitting a PR:

Once you have implemented the feature or bug fix in your branch, you will open a PR to the upstream cnf-testsuite repo. Before opening the PR ensure you rebased on the latest upstream, have added spec tests, if needed, all spec tests are passing.

In order to open a pull request (PR) it is required to be up to date with the latest changes upstream. If other commits are pushed upstream before your PR is merged, you will also need to rebase again before it will be merged.

Using the automated [pull request template](.github/PULL_REQUEST_TEMPLATE.md), please note a description of the changes, the type of change, the issue(s) related to the PR, how the changes have been tested and if updates are needed in the documentation.

For general advice on how to submit a pull request, please see [Creating a pull request](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request).

## Accepting a PR:

**Problem:** Pull requests from forks do not have the permissions to run through the github actions CI, so they will fail

**Solution:** Pull down the source from the fork and branch, then push up the source to the original cnf-testsuite repo.

1. Make a directory based on the forked user's name in the the pull request.
   `mkdir <contributor-username>`
   `cd <contributer-username>`
2. Clone the fork.
   `git clone git@github.com:<contributor-username>/cnf-testsuite.git`
   `cd cnf-testsuite`
3. Add the original cnf-testsuite repo.
   `git remote add cncf git@github.com:lfn-cnti/testsuite.git`
4. Checkout the pull request's branch.
   `git checkout <pull-request's-branch-name>`
5. Push the branch to the original cnf-testsuite repo.
   `git push <pull-request's-branch-name>`
6. Observe results of the github actions.
7. (optional) Accept the original pull request if the review and tests pass.
8. (optional -- changes required) Create a new PR, make changes, and merge into main (Github will automatically merge the original PR since it's changes will be included in the new PR)

## Community Meeting:

The CNTI community meets weekly on Tuesdays at 8:00 - 9:00 AM Pacific Time

- Meeting minutes are [here](https://docs.google.com/document/d/1yjL079TR0L1q__BRuhREeXfx5MtAmjPzbFZlZUeBsK4/edit)

## Thank you!

Thank you for your contributions. We appreciate your help and look forward to collaborating with you!
