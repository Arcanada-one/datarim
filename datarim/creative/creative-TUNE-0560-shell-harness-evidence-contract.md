---
task_id: TUNE-0560
artifact: creative
captured_at: 2026-08-02
captured_by: /dr-design
agent: architect
status: decided
schema_version: 1
consilium: false
---

# TUNE-0560 · Shell-Harness Child-Failure Propagation Evidence Gate

## Context

Several Datarim projects use shell‑based harnesses (bash scripts, `bats` suites,
custom command wrappers) whose exit code or a printed marker string is consumed
as evidence in QA and compliance reports. The recurring incident class
`harness-exit-status-misclassification` shows that a harness that exits 0 or
prints a green marker **does not prove the child command succeeded**.
Additionally, mutation‑gate or “expected‑red” tests that classify *any*
nonzero child exit as a caught defect have masked broken setup (missing
files, invalid arguments) as “caught”, producing false‑green evidence.

The originating reflection proposed the rule *“a green wrapper marker is
meaningless unless a deliberately failing child command makes the wrapper
return nonzero.”* It had not yet been promoted into the framework testing
skill. This ADR ratifies it as an evidence-acceptance contract and extends it
to sentinel-based mutation/expected-red proofs.

## Decision

**Ratify a shell‑harness evidence gate.** When an empirical shell wrapper’s
exit code or text marker is submitted as QA or compliance evidence, the
following three items **must** be present and independently verifiable in the
same report:

1. **Positive‑control proof**
   A passing child command (known‑green fixture) executed by the wrapper
   yields the wrapper’s exit code **0** *and* the wrapper’s declared PASS
   marker (e.g. a line containing `SUCCESS`). Both conditions are recorded
   (exit `0` AND the marker present). A positive‑only outcome is insufficient.

2. **Negative‑control proof**
   A **deliberately injected** failing child command (e.g. a sub‑call that
   exits `1`, or a command that is guaranteed to fail) makes the wrapper exit
   **nonzero**. The wrapper **must** preserve or propagate the child’s
   failure: a wrapper that always exits 0 regardless of the child is invalid.
   The negative control is executed in the same environment (same PATH, same
   Docker image, same file tree) as the real run.

3. **Sentinel‑matching for expected‑red / mutation proofs**
   When a wrapper is designed to “expect failure” (mutation check, integrity
   drill, expected‑red test), the child’s failure is considered **valid
   evidence of the intended guard only** when the wrapper’s diagnostic output
   **exactly matches** the named assertion/sentinel declared in the test plan
   (e.g. the string `MUTATION_CAUGHT: disk_full`). Any other nonzero exit
   whose output does **not** contain that sentinel is classified as **INVALID**
   evidence – not a caught mutation, not a red‑to‑red pass, not an acceptable
   failure. An unrelated setup failure (missing file, broken PATH,
   misconfigured argument) must be treated as **INVALID evidence**, requiring
   repair before the harness can be accepted.

The gate is cumulative: a harness must satisfy (1) and (2) to be considered
evidence‑grade. If the harness implements mutation or expected‑red behaviours,
(3) is additionally mandatory.

## Applicability

This decision applies when a shell layer sits between a child command and a
QA/compliance evidence claim **and that layer can alter, suppress, replace, or
reinterpret the child's status or output**. Examples include custom bash
wrappers, entrypoint wrappers, and make targets that convert child results into
their own marker or status. A native test runner invocation is not an extra
harness merely because it is launched from a shell. A Bats suite is in scope
only when an additional status-transforming wrapper sits between Bats and the
evidence claim. It applies to:

- New harnesses authored after ratification.
- Existing harnesses that participate in an active task’s verification
  (they must be retrofitted before the task’s next compliance cycle).
- Harnesses consumed across projects (they satisfy the gate once and the
  project‑local report may reference the canonical gate evidence).

The gate does **not** retroactively invalidate already‑archived tasks whose
evidence is closed, unless the task is reopened and the harness is re‑used.

## Required evidence (embedded in QA/compliance report)

For a harness `run-shadow-test.sh` that is claimed to verify condition `X`,
the QA/compliance report must include a subsection structured as follows:

```
### Shell‑harness gate evidence for run-shadow-test.sh

**Positive control**
- Child command: <exact child invocation that succeeds>
- Wrapper exit code: 0
- Wrapper PASS marker present: yes, line reads `SUCCESS`

**Negative control**
- Injected failing child: <exact failing command, e.g. `(exit 13)`>
- Wrapper exit code: 13 (non‑zero)
- Wrapper PASS marker absent

**Sentinel gate (if mutation/expected‑red)**
- Declared sentinel: `MUTATION_CAUGHT: disk_full`
- Mutation child that trips the guard: <child command that triggers sentinel>
- Wrapper output contains sentinel: yes
- Unrelated failure child: <e.g., `false` with wrong args>
- Wrapper output matches sentinel: no → **INVALID**, not counted as caught
```

Each line must be reproducible; the report must state the exact commands and
output captures.

## Rejected alternatives

1. **“Wrapper exit code alone is sufficient.”**
   Exit‑0 can hide a swallowed child failure (the wrapper ran but didn’t
   actually preserve the critical child path). The positive‑control marker +
   the negative‑control injection together close that gap.

2. **“Any nonzero exit counts as a caught mutation.”**
   This fails to distinguish between a genuine guard‑trigger and a broken
   harness (files missing, argument errors). Rejected; sentinel‑matching is
   required.

3. **“Manual review can catch these.”**
   Manual review is inconsistent and does not scale. The gate replaces
   operator judgement with a mechanical, replayable check. Rejected as
   insufficient for evidence repeatability.

4. **“A native runner's own tests prove an added wrapper.”**
   They prove the runner, not the status-transforming seam around it. The
   wrapper must be exercised with real positive and negative child controls at
   that seam. No extra gate is imposed where no such wrapper exists.

## QA / compliance wiring

The rule is added as **Gate 9** without replacing the existing live-smoke and
measurement-hygiene gates. `/dr-qa` and `/dr-compliance` must inspect the gate
whenever an in-scope status-transforming shell layer supplies evidence:

- Missing positive control, negative control, or named-sentinel proof is a
  fail-hard result; it cannot be downgraded to notes.
- A controlled substitution seam may be used to inject the child controls. It
  need not become a public product flag.
- An existing harness that lacks this proof is not assumed broken, but its
  evidence is rejected until the gate is satisfied.

## Mutation cases

Explicit classification rules for mutation and expected‑red tests:

| Wrapper state                           | Classification              |
|-----------------------------------------|-----------------------------|
| `exit==0` and PASS marker present       | PASS (genuine success)      |
| `exit!=0` and output has the exact named assertion | CAUGHT (valid mutation hit) |
| `exit!=0` and output lacks the exact named assertion | **INVALID** (harness defect) |
| `exit==0` but PASS marker absent        | **INVALID** (ambiguous)     |

An INVALID run must be repaired before the mutation check can be accepted;
it is not counted as either PASS or CAUGHT.

## Rollback

This decision may be rolled back only by an explicit superseding ADR that
names this decision, explains the replacement evidence model, and passes the
same review cycle. Effort, age of the harness, or a task-local waiver is not a
rollback path.

## Falsifiable acceptance criteria

The following criteria must be demonstrably true for the gate to be considered
ratified and operational:

- **AC‑1:** An in-scope shell harness that lacks negative-control evidence, or
  whose failing child does **not** make the wrapper exit nonzero, is rejected
  by QA and compliance.
- **AC‑2:** A mutation‑or‑expected‑red harness whose output does not match the
  declared sentinel is classified as INVALID, and a deliberate unrelated‑failure
  child (e.g. `stat /nonexistent`) produces INVALID, not CAUGHT.
- **AC‑3:** A shipped regression test proves a passing child, a failing child,
  a matching expected-red sentinel, and an unrelated setup failure.
- **AC‑4:** A harness that satisfies the gate and is later modified (e.g.
  wrapper rewritten without the negative control) fails the regression
  contract and cannot supply accepted evidence.
