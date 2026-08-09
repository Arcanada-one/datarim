---
task_id: TUNE-0574
artifact: reflection
captured_at: 2026-08-09
captured_by: /dr-compliance
reflection_basis: "967bb979218691f7"
---

# Reflection: TUNE-0574 -- Close task-ID provenance leaks across framework, site, and fleet

**Date:** 2026-08-09
**Complexity:** Level 4
**Duration:** One autonomous delivery and closure session.

## Summary

The implementation repaired the provenance scanner before cleaning the corpus,
expanded CI to every governed surface, aligned the public contract, and delivered
the companion-site parity change. The old scanner fails the expanded regression
contract, while the new scanner and the full framework suite pass. Protected
framework delivery, the signed release, installed-runtime convergence, final QA,
compliance, reflection, and archive reconciliation now complete the lifecycle.

## What Worked Well

- TDD made the original bypasses falsifiable: the isolated pre-fix gate failed
  24/50 cases, so GREEN could not be mistaken for tests written around the fix.
- Independent security and compliance reviews found four material gaps before
  delivery: scanner subprocess propagation, Markdown decoration laundering,
  strict shell mode, and executable mode on the site contract. Exact-head
  Semgrep found a fifth: the strict-mode edit had also set `IFS` globally. Each
  finding was reproduced or directly verified, fixed, and retained as durable
  evidence.
- Keeping the framework and site in isolated worktrees preserved unrelated local
  state and allowed exact-head and resulting-main proof for each repository.
- Separating implementation QA from release and fleet proof broke the release-
  gate cycle without claiming future evidence. The final replay promoted the
  three pending lifecycle expectations only after their live evidence existed.

## What Could Be Improved

- `incident_class: spec-graph-machine-readable-edge-drift` — the first QA draft
  described every V-AC in prose but omitted the exact `Evidence: V-AC-*` edge
  syntax, producing seven graph errors. The QA graph gate caught this immediately
  and the corrected report grades A. This is semantically adjacent to the prior
  Covers-line formatting incident in `reflection-TUNE-0530.md`, but the existing
  executable gate prevented shipment; no new promotion is justified.
- `incident_class: executable-mode-delivery-drift` — the first site change
  altered an executable contract script without preserving executable mode. A
  follow-up protected change restored it. No matching incident-class key or
  semantically equivalent case appears in the three recent reflections, so this
  is recorded as a novel lesson rather than promoted after one occurrence.
- `incident_class: bulk-validation-output-guard` — one bundled validation command
  was rejected by the runtime read guard because its possible output exceeded
  the direct-read threshold. Splitting it into bounded commands produced clearer
  evidence and avoided a needless large-output path. No recurrence was found.
- `incident_class: hosted-runner-queue-without-start` — the release publisher
  received no runner for 45 minutes. Before recovery, the job had zero steps,
  the deployment had zero statuses, and no release object existed. One bounded
  rerun of unfinished jobs for the same tag completed in 26 seconds. This is an
  external scheduling event, not a framework defect, so no evolution is proposed.

## Lessons Learned

- Fail-closed scanners need tests for their own subprocess failures, not only for
  policy matches. A clean result is trustworthy only when every producer in the
  scan pipeline is known to have succeeded.
- Normalization for Markdown policy labels must cover list, quote, table, task-
  list, and emphasis decorations. Testing only plain and bold prefixes leaves a
  laundering surface.
- File content and file mode are separate delivery properties. A shell contract
  can be byte-correct and still unusable through its documented direct entrypoint.
- Machine-readable trace edges belong in the artifact while evidence is written;
  human-readable mentions do not satisfy graph completeness.

## Evolution Proposals

No unapplied framework evolution is proposed in this pass. The scanner and gate
changes are the task's already-designed Class B contract delivery. The one
recurring documentation-edge lesson was caught by the existing mandatory
spec-graph gate, so it does not demonstrate a missing enforcement point. The two
novel process lessons have only one observed occurrence each; recurrence keys are
recorded above for future detection.

## Health Metrics

- Skills: 75 (above the optimization advisory threshold of 20).
- Agents: 19 (above the advisory threshold of 18).
- Commands: 28 (above the advisory threshold of 25).
- Largest skill observed: 786 lines (above the 500-line split advisory).

The framework may benefit from a separate `/dr-optimize` audit. It is not run
automatically and is not part of this task's provenance-gate Definition of Done.

## Follow-Up Tasks

None required for task closure. The optimization advisory is a maintenance
suggestion rather than an implementation gap. All release, fleet, and archive
work is already in this task's plan and must be completed here rather than moved
to a follow-up.

## Metrics

- Framework files changed before QA artifacts: 53.
- Framework lines added/removed before QA artifacts: 1457 / 325.
- Focused gate tests: 53 total.
- Full framework tests: 3257 total.
- Issues found by independent QA/CI: 5 material findings, all resolved.
