---
task_id: TUNE-0517
stage: qa
verdict: ALL_PASS
certified_sha: 2ff743e069d8c6cfcf16dfa915665cc2a86bf2ec
date: 2026-07-26
---

# QA Report: TUNE-0517

## Verdict

ALL_PASS. The Class A policy follows vendor-default semantics, keeps CLI
version awareness optional and fail-open, and does not change routing or exit
codes.

### Layer 1: PRD Alignment - SKIPPED

No task PRD exists; this is an L2 framework task driven by its task description.

### Layer 2: Design Conformance - SKIPPED

No design artifact exists.

### Layer 3: Plan Completeness - PASS

All plan steps were completed. The implementation added canonical policy,
declarative vendor-default tier configuration, consumer cross-links, an
opt-in timeout-bounded version hint, and regression tests.

### Layer 3b: Expectations Verification - PASS

All four expectations moved from `pending` to `met`. No override was used.

## Layer 3b - Per-Wish Detailed Report

#### Wish 1 - vendor-default-policy

**Evidence type:** static

**Check:** Canonical policy, configuration, and consumer cross-links were
checked at certified SHA `2ff743e069d8c6cfcf16dfa915665cc2a86bf2ec`.

**Command and result:**

```text
$ bats tests/tune-0517-vendor-default-policy.bats
1..8
ok 1 model assignment defines vendor-default policy and dependency boundary
...
ok 8 fleet version hint timeout is fail-open
Exit code: 0
```

**Verdict:** met - all eight policy assertions passed.

#### Wish 2 - latest-cli-advisory

**Evidence type:** static

**Check:** The policy was inspected for permission-aware, advisory-only CLI
guidance and preservation of routing and exit behavior.

**Command and result:**

```text
$ bats tests/tune-0517-vendor-default-policy.bats
ok 2 latest CLI guidance is permission-aware and advisory-only
Exit code: 0
```

**Verdict:** met - the required advisory semantics are present.

#### Wish 3 - fail-open-version-awareness

**Evidence type:** empirical

**Check:** The fleet selector was executed with success, failure, and hung
version probes while preserving the existing selector suite.

**Command and result:**

```text
$ bats tests/tune-0517-vendor-default-policy.bats plugins/dr-orchestrate/tests/test_fleet_selector.bats
1..20
...
ok 8 fleet version hint timeout is fail-open
...
ok 20 all backends unavailable produces no output
Exit code: 0
```

**Verdict:** met - runtime selection remained successful and timeout-bounded.

#### Wish 4 - depin-and-hygiene

**Evidence type:** empirical

**Check:** The full canonical test suite and repository validators were run
against the task branch.

**Command and result:**

```text
$ bats tests
1..2086
...
ok 2086 T10: no arguments -> exit 2
Exit code: 0

$ ./validate.sh
Validation passed
Exit code: 0
```

**Verdict:** met - 2,086 canonical tests passed and validation succeeded.

### Layer 4: Code Quality and Security - PASS

- `bash -n` passed for the changed resolver.
- repository-wide ShellCheck at warning severity passed.
- `yq '.' config/model-tiers.yaml` passed.
- `dev-tools/tests/public-surface-lint.bats` passed 17/17.
- Added-line ASCII and prohibited-literal scans passed.
- An isolated reviewer found three issues; all were corrected before this
  report: declarative tier consumption, a bounded version probe, and
  false-green Bats assertions.

## Known Baseline Outside the Canonical Gate

An exploratory expanded run including plugin-local suites reported three
failures in unchanged platform-stat helpers (`secrets_backend.sh` and
`security.sh`) on GNU `stat`. The canonical `bats tests` gate passed 2,086/2,086.
No TUNE-0517 file calls those helpers, and changing them would exceed the
Class A boundary by altering existing behavior.

## Deferred Items

None.

## Plain-language summary

### What changed

The framework now records model tiers as vendor-default intent and tells
adapters to omit a model override. Canonical guidance distinguishes runtime
CLI selection from project dependency selection. Optional CLI version hints
are explicitly advisory.

### What was verified

The full canonical suite passed all 2,086 tests. Focused policy and selector
tests passed 20/20, including a deliberately hung version command. Validation,
ShellCheck, YAML parsing, public-surface lint, ASCII checks, prohibited-literal
checks, commit signing, and remote branch checks also passed.

### What did not work

No task requirement failed. An expanded, noncanonical plugin sweep exposed
three pre-existing GNU `stat` portability failures in unchanged helpers; they
are outside this advisory-only change and do not weaken its evidence.

### What happens next

Compliance will replay the hard gates and archive will close the lifecycle on
the signed, pushed task branch. No production deployment or public release is
part of this task.
