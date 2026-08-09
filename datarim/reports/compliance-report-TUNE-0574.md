---
task_id: TUNE-0574
date: 2026-08-09
verdict: COMPLIANT
scope: pre-delivery framework implementation and delivered companion site
framework_sha: f9e39ae8b900e92e39788e68cdc5609e3047b0df
site_main_sha: 33cf4816d08c4b1ff3ced3948a291e1d3b80e83b
---

# Compliance Report — TUNE-0574

## Начальная задача

Close the task-ID provenance mechanism gaps across the public framework,
governed documentation, public site, release, and three installed runtimes.
Decide ordinary forks autonomously, preserve real illustrative examples only
inside narrow valid hatches, and do not claim lifecycle evidence before it
exists.

## Как решили

- Replaced the blind hatch stripper with a portable state machine that rejects
  malformed markers and provenance labels before suppressing illustration-only
  content.
- Made directory walking NUL-safe and fail-closed for symlinks, special files,
  unreadable inputs, binary inputs, invalid diff bases, scanner failures, and
  untracked files.
- Enforced exact repository-relative history exemptions, exact anchored
  exclusions, portable identifier boundaries, and the five documented text
  extensions across ten explicit CI callers.
- Classified the governed corpus, retained only legitimate examples in narrow
  hatches, and moved historical provenance to the designated evolution log.
- Changed the runtime hook probe to the semantic marker `missing read targets
  fail closed` and aligned the fleet procedure to that exact probe.
- Delivered the separate site no-hatch rule through protected changes, including
  a follow-up that restored executable mode after independent compliance found
  it missing.

## Артефакты задачи

### Implementation

- `scripts/task-id-gate.sh` — fail-closed scanner and directory/diff contract.
- `tests/task-id-gate.bats` — 53 behavior and failure-mode regressions.
- `.github/workflows/security.yml` — ten explicit governed callers.
- `skills/evolution/history-agnostic-gate.md` and `CLAUDE.md` — canonical
  contract alignment.
- `dev-tools/coworker-hook-guard.sh` and
  `documentation/how-to/fleet-hook-sync.md` — semantic fleet probe.
- `VERSION`, `CHANGELOG.md`, and version surfaces — release 2.65.0 inputs.
- Governed skills, commands, agents, templates, and documentation — classified
  corpus cleanup without weakening load-bearing rules.

### Workflow evidence

- `datarim/prd/PRD-TUNE-0574.md`
- `datarim/plans/TUNE-0574-plan.md`
- `datarim/tasks/TUNE-0574-expectations.md`
- `datarim/qa/qa-report-TUNE-0574.md`
- this compliance report

### Verification

- Focused gate suite: 53/53 passed.
- Full framework suite: 3257/3257 passed.
- Focused cross-gate suite: 91/91 passed.
- Site contract: 448 routes passed.
- Ten canonical task-ID gate calls: PASS.
- Body-English check: 132 skill files checked, PASS.
- Documentation references: 256 files checked, PASS.
- Stack-agnostic checks: PASS for skills, agents, commands, and templates.
- Version consistency: 2.65.0 across required surfaces, PASS.
- Repository validation: PASS.
- Native ShellCheck at warning severity: PASS.
- Exact-head Semgrep exposed a global `IFS` assignment. The assignment was
  removed, F2 now forbids its return, and focused tests plus independent review
  pass at the amended implementation SHA; protected CI is rerunning that SHA.
- Pre-commit Bandit and Gitleaks: PASS. The configured containerized ShellCheck
  hook lacked a usable container daemon; native ShellCheck supplied the check.
- Independent framework and site reviews: no unresolved finding.

## Следующие шаги

The exact framework revision is compliant and ready for protected delivery.
Framework merge, release publication, fleet synchronization, final QA replay,
and archive reconciliation remain mandatory downstream gates. This verdict does
not mark those proof layers complete.

---

### Step-by-step verdicts

<!-- gate:literal -->
| Step | Check | Verdict |
|---|---|---|
| 1 | Lint and formatting | PASS — ShellCheck and diff checks are clean |
| 2 | Tests | PASS — 3257 full, 53 focused, 91 cross-gate, 448 site routes |
| 3 | Coverage and controls | PASS — pre-fix 24/50 RED; positive and negative controls retained |
| 4 | CI/CD | PASS for delivered site; framework exact-head CI is the next protected gate |
| 5 | Security | PASS — fail-closed handling and independent review show no unresolved finding |
| 6 | Documentation | PASS — contract, PRD, plan, QA, version, and fleet guide agree |
| 7 | Compliance report | PASS — this report distinguishes implementation from downstream lifecycle proof |
<!-- /gate:literal -->

### Security baseline

- S1 strict shell mode is present in the changed gate: `set -euo pipefail`.
- All path traversal is NUL-delimited and anchored to canonical repository roots.
- Exemptions are exact paths rather than suffix matches.
- Invalid refs, unreadable inputs, binary content, special files, symlinks, and
  scanner subprocess errors fail closed.
- No secret material, private infrastructure detail, or personal identifier is
  recorded in committed task artifacts.

### Environment and production classification

The framework has no separate application test environment, so the framework
test-environment gate is `NO-TEST-ENV`; local runtime and CI are its relevant
verification surfaces. The companion site was deployed from protected
resulting main and received a live content readback. The framework fleet is a
post-release production-readiness stage and remains pending.

### Remaining risks

No unresolved implementation risk. The only open items are explicitly ordered
lifecycle operations: protected framework merge, release 2.65.0, three-machine
fleet readback, and final archive closure. Failure at any of those stages will
block the final task verdict rather than being converted into a waiver.

## Operator summary

**TUNE-0574 · Close task-ID provenance leaks across repo, site, and fleet**

**What was done**

The task asked for task-ID provenance to be removed from shipped framework and
site surfaces, with the enforcement mechanism repaired before cleanup. The
scanner, documentation, regression suite, corpus, semantic fleet probe, and
site rule now implement that requirement.

**What worked**

- The expanded tests detect the old bypasses and all pass after the fixes.
- Full framework verification, security checks, and independent reviews are
  green with no unresolved implementation finding.
- The site change passed protected checks, merged, deployed, and matched live
  resulting-main content.

**What didn't work or is still open**

- Nothing is open in the implementation-compliance scope. The framework has not
  yet been merged or released, and the three installed runtimes have not yet
  been synchronized; those are required downstream gates.

**What's next**

Deliver this exact revision through the protected framework branch, verify its
resulting-main tree, publish release 2.65.0, synchronize and read back all three
machines, then rerun QA and close the archive.
