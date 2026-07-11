# Deferred V-AC Waiver Clause — {TASK-ID}

> Use when a quantitative-threshold Acceptance Criterion (coverage %, latency
> budget, RPS, error rate, soak duration, etc.) cannot be measured at the
> current stage and the task proceeds with the AC explicitly deferred rather
> than silently marked "presumed met". Attach this clause inline in the PRD's
> AC list, the plan's V-AC table, or the QA/compliance report — wherever the
> thresholded AC is declared.
>
> Canonical reference: `skills/compliance/SKILL.md` § Quantitative-threshold
> AC enforcement (Software Checklist step 4). A deferred thresholded AC
> without this clause is a compliance finding, not a pass.

## Waiver fields (all four required)

- **Status: measured vs. deferred.** State which. If deferred, name the
  specific measurement that is missing (e.g. "coverage tool not installed
  on target host", "soak window not yet elapsed") — not just "not done".
- **Gating dependency.** The concrete blocker that must resolve before the
  measurement can run — typically another task ID (e.g. "an INFRA-XYZ
  tooling-install task", "a follow-up perf task"), a missing tool, or an
  external event. Name the blocker, not a vague "later".
- **Follow-up condition.** The exact trigger that re-opens this AC for
  measurement — a task ID landing, a time window elapsing, an environment
  becoming available. Must be checkable by a future reader without asking
  the original author.
- **Timestamp + owner.** ISO 8601 date the waiver was recorded, and who
  recorded it (agent role or operator handle) — so a stale waiver is
  visible at a glance during a later compliance pass.

## Fill-in template

```
V-AC-{N} — {short AC description, e.g. "≥80% line coverage"}
- Status: deferred (measurement: {what's missing})
- Gating dependency: {task-id or blocker, e.g. "an INFRA-XYZ tooling-install task"}
- Follow-up condition: {trigger that re-opens this AC}
- Recorded: {YYYY-MM-DD} by {owner}
```

## Non-example (what this replaces)

Do not carry a thresholded AC forward as bare prose ("presumed met", "will
verify later") with no structured fields — a future compliance pass has no
way to tell a forgotten AC from an intentionally deferred one. The four
fields above make the deferral auditable instead of implicit.

## Source

A quantitative-threshold Acceptance Criterion was deferred during a
compliance pass without a structured waiver, surfacing as the defect class
"deferred-AC forgotten" — a later reader had no way to tell an intentional
deferral from a forgotten one. This template closes that gap by giving
every deferred thresholded AC the same four-field shape.
