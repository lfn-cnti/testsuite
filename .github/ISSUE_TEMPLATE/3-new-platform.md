---
name: New Platform Test
about: Creating a new platform testsuite test
title: "[Platform]"
labels: platform
assignees: ""
---

## [Acceptance Criteria] (TBD)

### CATEGORY_NAME test: DESCRIPTIVE_TEST_NAME

**Short description of platform test:**

- goal of this platform test

**Test Category**

- ADD CATEGORY_NAME (e.g. State, Security, etc from [README](https://github.com/lfn-cnti/testsuite/blob/main/README.md#cnti-testsuite))

**Proof of Concept** (if available)

- [ ] link to proof of concept of new workload test

---

### Implementation Tasks: TBD

**Environment set up tasks:**

- [ ]

**Upstream tool set up tasks: (test suite + upstream tools)**

- [ ]

**CNF setup Tasks**

- [ ]

**Sample CNF tasks:**

- [ ]

**Code implementation tasks:**

- [ ]

**Documentation tasks:**

- [ ] Update [Pseudo Code md](https://github.com/lfn-cnti/testsuite/blob/main/PSEUDO-CODE.md) if needed
- [ ] Update [TEST_DOCUMENTATION md](../../docs/TEST_DOCUMENTATION.md) if needed
- [ ] Update [installation instructions](../../install.md) if needed

### QA tasks

Dev Review:

- [ ] walk through A/C
- [ ] do you get the expected result?
- [ ] if yes,
  - [ ] move to `Needs Peer Review` column
  - [ ] create Pull Request and follow check list
  - [ ] Assign 1 or more people for peer review
- [ ] if no, document what additional tasks will be needed

Peer review:

- [ ] walk through A/C
- [ ] do you get the expected result?
- [ ] if yes,
  - [ ] move to `Reviewer Approved` column
  - [ ] Approve pull request
- [ ] if no,
  - [ ] document what did not go as expected, including error messages and screenshots (if possible)
  - [ ] Add comment to pull request
  - [ ] request changes to pull request
