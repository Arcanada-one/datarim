---
id: {TASK-ID}
title: {short title, ≤80 chars}
status: archived
completed_date: {YYYY-MM-DD}
complexity: L{1-4}
type: {framework|infra|content|bugfix|...}
project: {Datarim|Arcanada|...}
related: []
archive_doc: documentation/archive/{subdir}/archive-{TASK-ID}.md
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 0
  false_positive: 0
  n_a: false
  dogfood_window: "{window-id}"
---
<!--
verification_outcome field semantics:
- caught_by_verify: integer count of high/medium gaps caught BEFORE /dr-archive (i.e., problems found during /dr-verify that were fixed or documented before archival)
- missed_by_verify: integer count of gaps that escaped /dr-verify and required post-archive followup (tracked in a new task or bug report)
- false_positive: integer count of findings flagged by /dr-verify that were triaged as not real (e.g., misunderstanding, tool error, already addressed)
- n_a: boolean, set to true when /dr-verify was NOT run (e.g., task abandoned, dry run, or emergency close). When true, the three counts above should be 0.
- dogfood_window: string, active prospective-measurement window identifier (placeholder `{window-id}`). Used by aggregation tool dev-tools/measure-prospective-rate.sh as a grouping key.
-->

# Archive: {TASK-ID} -- {Title}

## Outcome

(What was delivered. Concise 2-5 sentences matching task overview.)

## Verification Summary

- **Layers run:** {list of verification layers, e.g., /dr-verify, /av sync, manual QA}
- **Highest severity:** {none | low | medium | high}
- **Verdict:** {pass | pass_with_notes | fail | not_run}
- **Audit log path:** {path to /dr-verify output or N/A}

## Final Acceptance Criteria

| AC | Status | Evidence |
|---|---|---|
| AC-1: {description} | {pass/fail/partial} | {link or summary} |
| AC-2: {description} | {pass/fail/partial} | {link or summary} |

## Known Outstanding State / Operator Handoff

(Any residual technical debt, deferred improvements, or configuration steps the next operator should know. Empty if none.)

## Related

- Parent PRD: (path or none)
- Plan: (path or none)
- Reflection: (path or none)
- Follow-ups: (task IDs or none)

## Lessons Learned

(Compact 3-5 bullet mirror of reflection. Focus on what to repeat, what to avoid, and what to apply to future tasks.)
