---
name: Bug Report
about: Create a report to help us improve
title: "[BUG]"
labels: bug
assignees: ""
---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Device (please complete the following information):**

- OS [e.g. Linux, iOS, Windows, Android]
- Distro [e.g. Ubuntu]
- Version [e.g. 18.04]
- Architecture [e.g. x86, arm]
- Browser [e.g. chrome, safari]

**How will this be tested? aka Acceptance Criteria (optional)**

(optional: unnecessary for things like spelling errors and such)

Once this issue is address how will the fix be verified?

**Additional context**
Add any other context about the problem here.

---

> NOTE: you can enable higher logging level output via the command line or ENV variable to help with debugging.

```
# cmd line
./cnti-testsuite -l debug test

# make sure to use -- if running from source
crystal src/cnti-testsuite.cr -- -l debug test

# ENV variable
CNTI_TESTSUITE_LOG_LEVEL=DEBUG ./cnti-testsuite test
```

Check [usage documentation](https://github.com/lfn-cnti/testsuite/blob/main/USAGE.md) for more info about invoking commands and logging
