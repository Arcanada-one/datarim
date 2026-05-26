---
name: health-controller-stub-detector
description: Surface hard-coded stub literals (pending-integration, not-implemented, stub) in health/status controllers at /dr-do, before /dr-qa wish gating.
current_aal: 1
target_aal: 2
---

# Health Controller Stub Detector — Skill

## Purpose

Health/status endpoint controllers often ship with hard-coded 'pending-integration' / 'not-implemented' / 'stub' status literals when the cross-service wire-up is deferred. These literals are intentional placeholders, but they create a contract gap: consumer code may treat the literal as authoritative state, and acceptance criteria that probe /health endpoints may pass on stub data without catching the missing wire-up. This skill provides a /dr-do checklist gate to surface such stubs before they reach /dr-qa or /dr-compliance.

## When to invoke

Invoked by /dr-do Step 7 (Implementation Notes) when task touches files matching:
- *health*controller*
- *health*service*
- *liveness*
- *readiness*
- *status*indicator*
- Equivalent role-named files in any stack

## Detector

Grep on the following literal patterns in diff added lines:
- 'pending-integration'
- 'not-implemented'
- 'not_implemented'
- 'unimplemented'
- '"stub"'
- placeholder-status (varies by team convention — operator extends pattern set)

Recommended shell form (one-liner template — stack-agnostic, runs on any POSIX):
```bash
git diff HEAD~1..HEAD -- '*health*' '*status*indicator*' '*liveness*' '*readiness*' | grep -E '^\+' | grep -E "'pending-integration'|'not-implemented'|'not_implemented'|'stub'|'unimplemented'"
```

## Disposition matrix

| Match found | Action |
|-------------|--------|
| ≥1 match in added lines | Surface to operator: «found N stub literal(s) — for each, either implement now OR document in § Out of Scope + open backlog item» |
| Match in untouched lines (pre-existing) | Non-blocking advisory; record in Implementation Notes as 'pre-existing stub literal not modified' |
| No match | PASS |

## Operator decision rules

For each stub literal found in NEW added lines (delta vs HEAD~1):
1. **Implement now.** Wire up the live probe (probe downstream /health endpoint, return real status); remove literal.
2. **Defer explicitly.** Move the placeholder to a clearly-labelled deferred section of the controller, add inline reason comment (e.g. 'TODO(ARCA-NNNN): wire health-reporter for modelConnector'), and open a backlog item with pattern '<area>-NNNN — <controller> health-reporter wire-up for <downstream>'.
3. **Out of Scope on this task.** Document in task-description § Out of Scope: 'health/<indicator> remains stub until <follow-up-id>'.

## Anti-patterns

- Leaving a stub literal without backlog tracking — silent contract gap surfaces at /dr-qa wish gating.
- Treating hard-coded literal as «PASS» on /health probe assertion — health endpoint may return 200 with stub status, fooling smoke tests.
- Acceptance criterion citing /health response without cross-checking that the field reflects real downstream probe.

## Source

Prior incident class: a multi-modal request-flow wire-up landed end-to-end in a downstream service, but its `/health.<downstreamName>` indicator remained a hard-coded `'pending-integration'` literal in the upstream health controller. Wish gating for the request flow incorrectly treated the `/health` indicator as proof of wire-up, when it was a separate (deferred) health-reporter integration. The contract gap surfaced only at the compliance gate — late in the pipeline — and blocked the verdict cycle until the operator reconciled the wording. This skill catches the pattern earlier (at /dr-do) by grepping added lines for known stub literals and prompting one of three explicit dispositions before the task advances.

Provenance: see `docs/evolution-log.md` for the archive entry that motivated this skill.

## Cross-references

- /dr-do § Step 7 — invokes this skill when task touches health/status files.
- skills/expectations-checklist/SKILL.md — wish formulation should not rely on /health literal as wire-up proof.
