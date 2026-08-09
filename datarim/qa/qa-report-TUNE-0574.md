---
task_id: TUNE-0574
date: 2026-08-09
verdict: ALL_PASS
scope: pre-delivery implementation and companion-site delivery
reviewed_framework_sha: f9e39ae8b900e92e39788e68cdc5609e3047b0df
reviewed_site_main_sha: 33cf4816d08c4b1ff3ced3948a291e1d3b80e83b
---

# QA Report — TUNE-0574

**Reviewer:** Reviewer Agent plus independent clean-context reviewers
**Overall Verdict:** ALL_PASS

This is the required pre-release QA pass. Framework merge, release publication,
fleet synchronization, and archive are deliberately recorded as downstream
gates, not as evidence already obtained. The QA stage will be replayed after
those gates to bind the final lifecycle evidence.

---

### Layer 1: PRD Alignment — PASS

| Requirement group | Evidence | Verdict |
|---|---|---|
| D-REQ-01 through D-REQ-04 | One-target gate, exact CI caller list, balanced hatch parser, provenance-label rejection, exact exemptions, and fail-closed traversal are implemented and exercised by 53 focused cases. | PASS |
| D-REQ-05 through D-REQ-06 | The hook uses the semantic marker `missing read targets fail closed`; the fleet guide uses the identical probe; Rule 8 and the gate contract match the implementation. | PASS |
| D-REQ-07 through D-REQ-08 | The isolated pre-fix gate returned 1 with 24/50 cases failing; the fixed focused suite passes 53/53 and the full suite passes 3257/3257. | PASS |
| D-REQ-09 | The site rejects a novel prefix, passes 448 routes, landed through protected PRs, and deployed from resulting main. | PASS |
| D-REQ-10 through D-REQ-11 | Version and release inputs are ready. Release publication and fleet readback are post-merge gates and remain pending without being represented as PASS. | NOT REACHED |

**V-AC status:** V-AC-1, V-AC-2, V-AC-3, V-AC-4, V-AC-6, V-AC-7,
and V-AC-8 pass. V-AC-5 and V-AC-9 are downstream lifecycle checks.

---

### Layer 2: Design Conformance — PASS

The selected POSIX-awk state machine remains inside the one-target Bash CLI.
The implementation uses portable token boundaries, marker-only balanced hatch
grammar, stateful provenance-label rejection, NUL-delimited directory walking,
exact repository-relative exemptions, and explicit exit codes 0/1/2. It scans
only the five contract extensions in directory mode, while direct file mode
fails closed for unsupported input kinds.

Autonomous fork decisions are recorded in the plan. The notable decisions were
to retain the public one-target interface, treat malformed hatch syntax as an
independent finding, validate diff bases before walking, scan untracked files in
full-file mode, and keep the site on its stricter no-hatch policy.

The final independent framework review found no correctness, security, scope,
or maintainability defect at the reviewed framework SHA. The independent site
review found no defect at the reviewed resulting-main SHA.

---

### Layer 3: Plan Completeness — PASS

| Plan task | Status | Notes |
|---|---|---|
| 1. Regression suite and RED | Done | Isolated pre-fix control returned 1; focused fixed suite passes. |
| 2. Fail-closed gate | Done | Parser, traversal, diff, exact exemption, and error contracts implemented. |
| 3. CI and contract | Done | All ten callers are explicit and documentation matches enforcement. |
| 4. Corpus cleanup | Done | Governed corpus passes; provenance remains only on exact history surfaces. |
| 5. Public site | Done | Protected site changes merged and resulting-main deployment succeeded. |
| 6. Version and verification | Done | Version 2.65.0 and changelog ready; all local verification is green. |
| 7. Independent QA/compliance | Done for pre-delivery | Clean-context reviewers report no unresolved high or medium implementation issue. |
| 8. Protected framework delivery | Not reached | Starts after this QA/compliance checkpoint. |
| 9. Release | Not reached | Requires verified resulting main. |
| 10. Fleet | Not reached | Requires the published release. |
| 11. Archive | Not reached | Requires all prior proof layers. |

**Skipped steps:** None. Sequential downstream steps are not skips.

**Unplanned additions:** A scanner-subprocess failure regression, Markdown
decoration laundering regressions, strict-mode enforcement, and a site file-mode
follow-up were added after independent review. Each closes a concrete defect.

---

### Layer 3b: Expectations Verification — PASS

**Items verified:** 7
**Status transitions written:** 7

| # | wish_id | Current status | Notes |
|---|---|---|---|
| 1 | close-all-gate-gaps | met | 53 focused cases pass. |
| 2 | classify-and-clean-governed-corpus | met | Ten governed targets pass. |
| 3 | preserve-prefixed-red-proof | met | Pre-fix 24/50 failed; fixed 53/53 passed. |
| 4 | site-generic-gate-and-deploy | met | Site contract, protected merge, deploy, and readback pass. |
| 5 | framework-release-provenance | pending | NOT REACHED: protected merge and release follow QA. |
| 6 | fleet-three-machine-readback | pending | NOT REACHED: fleet sync follows release. |
| 7 | complete-quality-and-archive | pending | NOT REACHED: closure follows delivery and fleet proof. |

**Validator verdict:** PASS. Pending items are accepted by the routing contract
and will be re-evaluated, not waived, during the post-release QA replay.

## Layer 3b — Per-Wish Detailed Report

#### Wish 1 — close-all-gate-gaps: The gate closes every documented mechanism gap

**Evidence type:** empirical

Evidence: V-AC-1 — the focused runtime suite passes all documented gate modes.

**Что было сделано для проверки:** The complete focused behavior suite was run at the
reviewed framework SHA, including malformed markers, label laundering,
boundaries, exact exemptions, file kinds, directory discovery, and diff errors.

**Команда + результат:**
```text
$ bats tests/task-id-gate.bats
1..53
ok 53 directory-mode scanner failures return 2
Exit code: 0
```

**Measured result:** 53 passed, 0 failed.

**Verdict:** met — exit 0 and 53/53 cases passed.

#### Wish 2 — classify-and-clean-governed-corpus: Every shipped task-ID occurrence is classified

**Evidence type:** static

Evidence: V-AC-2 — every canonical target returns clean after classification.

**Что было сделано для проверки:** The raw inventory was classified against the gate
contract, then the one-target gate was run separately against all ten canonical
targets. The two exact history surfaces remain explicit exemptions.

**Команда + результат:**
```text
$ for target in <ten canonical targets>; do scripts/task-id-gate.sh "$target"; done
PASS: clean
(repeated for all ten targets)
Exit code: 0
```

**Measured result:** 10 clean targets, 0 policy findings.

**Verdict:** met — 10/10 targets returned exit 0 with `PASS: clean`.

#### Wish 3 — preserve-prefixed-red-proof: RED evidence detects the original defect

**Evidence type:** empirical

Evidence: V-AC-7 — the isolated pre-fix implementation fails the expanded suite.

**Что было сделано для проверки:** The expanded suite was run with an isolated copy of the
pre-fix gate, then the fixed gate was run with the same behavior contract.

**Команда + результат:**
```text
$ TASK_ID_GATE_OVERRIDE=<isolated-old-gate> bats tests/task-id-gate.bats
24 of 50 tests failed
Exit code: 1
$ bats tests/task-id-gate.bats
1..53
Exit code: 0
```

**Measured result:** meaningful RED followed by complete GREEN.

**Verdict:** met — the old code fails meaningfully and the fixed code passes.

#### Wish 4 — site-generic-gate-and-deploy: The public site enforces the generic no-hatch rule

**Evidence type:** empirical

Evidence: V-AC-8 — the protected site main passes its contract and deployed.

**Что было сделано для проверки:** The site control rejects a novel prefix and accepts
adjacent non-identifiers. The clean contract was run locally and in exact-head
CI; protected resulting main was deployed and read back.

**Команда + результат:**
```text
$ ./tests/site-contract.sh
PASS: site contract (448 routes checked)
Exit code: 0
CI verify: 31318711449 SUCCESS; 31319925573 SUCCESS
Deploy: 31318861223 SUCCESS; 31319970500 SUCCESS
```

**Measured result:** 448 routes clean; final site main is
`33cf4816d08c4b1ff3ced3948a291e1d3b80e83b`.

**Verdict:** met — local contract, exact-head CI, deployment, and readback pass.

#### Wish 5 — framework-release-provenance: Framework delivery and release are immutable

**Evidence type:** empirical

Evidence: V-AC-9 — version inputs pass; immutable release evidence is pending.

**Что было сделано для проверки:** Local merge readiness, version surfaces, and release
inputs are green at the reviewed framework SHA. Protected delivery is the next
sequential stage.

**Команда + результат:**
```text
$ dev-tools/check-version-consistency.sh
PASS: version consistency 2.65.0
Exit code: 0
$ ./validate.sh
ALL CHECKS PASSED
Exit code: 0
```

**Measured result:** pre-release inputs pass; current status remains pending.

**Verdict:** pending — release URL and tag target are NOT REACHED.

#### Wish 6 — fleet-three-machine-readback: The released runtime is verified on all machines

**Evidence type:** empirical

Evidence: V-AC-5 — the semantic probe is wired; remote fleet evidence is pending.

**Что было сделано для проверки:** The installed hook probe and fleet documentation are
aligned locally. Remote readback requires the released artifact and is the
post-release stage.

**Команда + результат:**
```text
$ grep -F 'missing read targets fail closed' dev-tools/coworker-hook-guard.sh
# missing read targets fail closed
Exit code: 0
```

**Measured result:** current status remains pending.

**Verdict:** pending — three-machine version, drift, and marker readbacks are NOT REACHED.

#### Wish 7 — complete-quality-and-archive: Full quality and lifecycle closure

**Evidence type:** empirical

Evidence: V-AC-1 — full and focused implementation verification is green.

**Что было сделано для проверки:** Local full and focused verification, site delivery, and
independent review are complete. Archive reconciliation correctly remains last.

**Команда + результат:**
```text
$ bats tests/ dev-tools/tests/
1..3257
Exit code: 0
$ bats tests/task-id-gate.bats tests/check-body-english.bats tests/check-doc-refs.bats tests/stack-agnostic-gate.bats
1..91
Exit code: 0
```

**Measured result:** pre-delivery quality is green; lifecycle status remains
pending until merge, release, fleet readback, and archive complete.

**Verdict:** pending — quality is green; final archive evidence is NOT REACHED.

---

### Layer 3c: Automatic Spec-Graph Verification — PASS

The PRD-to-plan graph is grade A. D-REQ-01 through D-REQ-11 are covered. Two
informational duplicate `Covers` annotations do not change requirement coverage
or execution.

---

### Layer 4: Code Quality — PASS

**Tests:** 3257 passed, 0 failed in the full suite; 53/53 focused gate tests;
91/91 focused cross-gate tests; 448 site routes.

**Security issues:** 0 unresolved high or medium findings. Independent review
identified three real gaps during development: scanner failure propagation,
decorated label normalization, and strict shell mode. Exact-head Semgrep then
rejected a global `IFS` mutation introduced with strict mode; F2 was inverted
RED/GREEN to forbid that mutation. Each defect is fixed and retained as a
regression or blocking security check.

**Anti-patterns:** 0 unresolved. ShellCheck passes for tracked shell files at
warning severity. Bandit and Gitleaks pass through pre-commit. The configured
containerized ShellCheck hook could not access a container daemon in this
environment; native ShellCheck supplied the same static-analysis gate.

**Playwright pass:** SKIPPED — no frontend implementation was changed.

| DoD criterion | Status |
|---|---|
| Widened gate and fail-closed parser | Met |
| Governed corpus classification | Met |
| RED/GREEN proof | Met |
| Site contract and deployment | Met |
| Framework protected merge | NOT REACHED |
| Release 2.65.0 | NOT REACHED |
| Three-machine fleet readback | NOT REACHED |
| Final archive reconciliation | NOT REACHED |

---

## Summary

**Layers executed:** 6

**Results:** Layer 1 PASS, Layer 2 PASS, Layer 3 PASS, Layer 3b PASS, Layer 3c
PASS, Layer 4 PASS.

**Overall:** ALL_PASS for protected framework delivery. No downstream proof is
treated as already complete.

## Deferred Items (session-scoped)

None — no deferrals this session. Merge, release, fleet synchronization, and
archive are planned sequential lifecycle stages with explicit acceptance
criteria, not deferred defects.

## Plain-language summary

## Operator summary

**TUNE-0574 · Close task-ID provenance leaks across repo, site, and fleet**

**What was done**

The task asked for a complete repair of task-ID provenance enforcement across
the framework, public site, release path, and installed fleet. The framework
scanner and its documentation are repaired, the governed corpus is clean, and
the stricter site rule has been merged and deployed.

**What worked**

- The original scanner fails 24 of 50 expanded cases, proving the regression
  suite detects the old defects; the fixed scanner passes all 53 current cases.
- The full framework suite passes 3,257 tests, all ten governed targets are
  clean, and independent reviewers found no unresolved implementation defect.
- The site checks 448 routes, merged through protected changes, and the live
  readback matches its resulting-main revision.

**What didn't work or is still open**

- Nothing failed in the pre-delivery QA scope. Framework merge, release 2.65.0,
  three-machine synchronization, and archive are still open because they are
  sequential stages that begin after this QA checkpoint.

**What's next**

Run final compliance on this exact framework revision, then open the protected
framework change. After resulting-main verification, publish the release,
synchronize all three machines, replay QA with the live evidence, and archive.
