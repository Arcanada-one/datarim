---
task_id: TUNE-0574
date: 2026-08-09
verdict: ALL_PASS
scope: final implementation, protected delivery, release, fleet, and archive replay
reviewed_framework_sha: c0e283eb22b9b052197f93f96ab165e833b9e17f
reviewed_site_main_sha: 33cf4816d08c4b1ff3ced3948a291e1d3b80e83b
---

# QA Report — TUNE-0574

**Overall Verdict:** ALL_PASS

The final replay binds implementation evidence to protected resulting main,
the public release, the deployed companion site, installed runtime readbacks,
and the archive/state changes in this closure branch.

## Layer 1: PRD Alignment — PASS

| Requirement | Evidence | Verdict |
|---|---|---|
| D-REQ-01 through D-REQ-04 | The one-target scanner uses a balanced fail-closed parser, rejects provenance laundering, walks the five contract extensions with NUL-safe traversal, validates diff inputs, and applies exact canonical exemptions. | PASS |
| D-REQ-05 through D-REQ-06 | The hook and fleet guide share `missing read targets fail closed`; Rule 8 and the gate contract describe the same ten scopes and behavior. | PASS |
| D-REQ-07 through D-REQ-08 | The isolated old scanner failed 24/50 cases with exit 1; the fixed focused suite passed 53/53 and the complete suite passed 3257/3257. | PASS |
| D-REQ-09 | The site novel-prefix control failed before the fix, the clean contract passed 448 routes, and protected resulting main deployed successfully. | PASS |
| D-REQ-10 through D-REQ-11 | Release 2.65.0 is published from resulting main with verified artifacts; all current named runtime surfaces match that release and the separately gated checkout is unchanged. | PASS |

Evidence: V-AC-1 — `bats tests/task-id-gate.bats` passed 53/53.

Evidence: V-AC-2 — each of the ten canonical targets returned `PASS: clean`.

Evidence: V-AC-3 — marker grammar, labels, extensions, boundaries, and failure
paths have named regression cases.

Evidence: V-AC-4 — exact history exemptions and anchored fixture exclusions pass;
suffix-spoof and nested-exclusion controls fail as required.

Evidence: V-AC-5 — the three current named runtime surfaces report version
2.65.0, exact head `c0e283eb22b9b052197f93f96ab165e833b9e17f`, ten clean
scope scans, and the semantic hook marker.

Evidence: V-AC-6 — Rule 8, the contract, CI callers, and implementation agree.

Evidence: V-AC-7 — the isolated pre-fix scanner produced exit 1 with 24/50
failures; the fixed scanner produced exit 0 with 53/53 passes.

Evidence: V-AC-8 — site verification runs `31318711449` and `31319925573`,
deployment runs `31318861223` and `31319970500`, and the final 448-route
readback all succeeded.

Evidence: V-AC-9 — PR 352 merged to
`c0e283eb22b9b052197f93f96ab165e833b9e17f`; tag `v2.65.0` targets that
commit; release run `31322665918` attempt 2 succeeded.

## Layer 2: Design Conformance — PASS

The selected POSIX-awk state machine remains inside the public one-target Bash
CLI. It uses portable token boundaries, marker-only balanced hatch grammar,
stateful label rejection, NUL-delimited traversal, exact repository-relative
exceptions, and exit codes 0/1/2. The public site intentionally keeps its
stricter no-hatch rule.

Independent security review drove scanner-failure, decorated-label, path-kind,
diff-error, strict-mode, and no-global-IFS tests. Independent final framework
and site reviews found no unresolved correctness, security, or maintainability
finding.

## Layer 3: Plan Completeness — PASS

| Plan group | Status | Evidence |
|---|---|---|
| Scanner, tests, CI, contract, corpus | Done | 53 focused tests, ten clean targets, and full validation pass. |
| Site parity | Done | Protected changes merged; exact resulting-main deploy and live readback pass. |
| Framework delivery | Done | PR 352 exact head had 57 terminal checks with zero failures; resulting-main workflows pass. |
| Release | Done | Five assets published; checksum, two signatures, attestation, SBOM, and archive version verified. |
| Fleet | Done | Primary checkout, secondary checkout, and secondary user runtime match the release; gated checkout unchanged. |
| Archive | Done | Archive, expectations, reports, reflection, release audit, and thin indexes reconcile in this branch. |

No step was skipped or converted into a waiver. The 45-minute runner-less
release attempt had no steps or release object; one bounded rerun of unfinished
jobs for the same tag completed successfully.

## Layer 3b: Expectations Verification — PASS

| # | wish_id | Status | Evidence |
|---|---|---|---|
| 1 | close-all-gate-gaps | met | 53/53 focused behavior cases pass. |
| 2 | classify-and-clean-governed-corpus | met | Ten governed targets pass with exact exemptions. |
| 3 | preserve-prefixed-red-proof | met | Old scanner 24/50 RED; fixed scanner 53/53 GREEN. |
| 4 | site-generic-gate-and-deploy | met | 448 routes, protected merge, deploy, and readback pass. |
| 5 | framework-release-provenance | met | Exact PR/main/tag/run and five verified assets. |
| 6 | fleet-three-machine-readback | met | Three current named runtime surfaces match; gated checkout unchanged. |
| 7 | complete-quality-and-archive | met | Full QA/compliance, reflection, archive, and state reconciliation agree. |

The routing validator passes with seven met wishes and no override.

## Layer 3c: Automatic Spec-Graph Verification — PASS

The PRD-to-plan-to-QA graph retains grade A coverage for D-REQ-01 through
D-REQ-11. Two informational duplicate `Covers` bindings do not affect coverage.

## Layer 4: Code and Delivery Quality — PASS

- Full framework suite: 3257 passed, 0 failed.
- Focused scanner suite: 53 passed, 0 failed.
- Focused cross-gate suite: 91 passed, 0 failed.
- Site contract: 448 routes passed.
- Body-English, documentation references, stack-agnostic, version consistency,
  repository validation, ShellCheck, Bandit, Gitleaks, and Semgrep: PASS.
- Resulting-main framework workflows: PASS at the release commit.
- Release verification: five assets; checksum OK; two `Verified OK` signature
  results; build attestation exit 0; 45 SBOM components; archive version 2.65.0.
- Playwright: SKIP — no browser UI implementation changed.
- Framework test environment: NO-TEST-ENV — framework behavior is exercised by
  local runtime, exact-head CI, installed-runtime readback, and site deployment.

## Summary

All PRD requirements, seven expectations, nine V-AC groups, the Definition of
Done, and the independent-review findings are satisfied with empirical or
static evidence. No unproven acceptance criterion remains.

## Operator summary

**TUNE-0574 · Close task-ID provenance leaks across framework, site, and fleet**

**Что было сделано / What was done**

Task-ID provenance enforcement now covers every governed framework and
documentation surface, rejects malformed or laundered hatches, and is matched
by the public contract, CI, site rule, release, and installed runtimes. Real
historical stamps were removed without erasing their load-bearing rationale,
while rendered examples remain inside narrow valid hatches. The task also
reconciles its expectations, final reports, reflection, release audit, archive,
and active-task indexes.

**Что получилось / What worked**

Meaningful RED/GREEN controls exposed the original bypasses. Protected
framework and site delivery, complete tests, exact-main workflows, signed
release artifacts, and runtime readbacks all converge on the intended state.
Independent reviewers found scanner-failure, label-normalization, shell-mode,
global-IFS, and executable-mode defects before closure; every finding was
reproduced or directly verified and retained as a regression or delivery check.

**Что не получилось / осталось открытым / What didn't work or is still open**

The first release publish attempt remained runner-less for 45 minutes. A single
side-effect-free bounded rerun for the same tag completed successfully. Before
that retry, the job had no steps, the deployment had no statuses, and no release
object existed. The current inventory also resolved the third fleet label to a
per-user runtime on the secondary host instead of a retired standalone node;
the separately gated checkout was verified unchanged. No product defect remained.

**Что дальше / What's next**

Merge this protected closure branch after its exact-head checks. That landing
adds only lifecycle evidence and state reconciliation; released behavior is
already immutable at version 2.65.0. No product, release, fleet, or framework
remediation remains, and no follow-up task or operator action is required.
