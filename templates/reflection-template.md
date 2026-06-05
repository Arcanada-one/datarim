---
task_id: {TASK-ID}
artifact: reflection
captured_at: {date}
captured_by: {/dr-compliance | /dr-archive}
reflection_basis: "{16-hex sha256 prefix of the compliance report this reflection summarises, or empty when no compliance report existed}"
---

# Reflection: {TASK-ID} -- {Title}

**Date:** {date}
**Complexity:** Level {1-4}
**Duration:** {time spent}

> `reflection_basis` is stamped by whichever stage wrote this file (`/dr-compliance`
> on a passing verdict, else `/dr-archive` Step 0.5). `/dr-archive` re-runs reflection
> only when this file is absent, the field is absent, or the field no longer matches
> the current compliance report (see `dev-tools/reflection-freshness.sh`).

## Summary
(What was accomplished)

## What Worked Well
-

## What Could Be Improved
-

## Lessons Learned
-

## Evolution Proposals

### Proposal 1
- **Category:** {skill-update | agent-update | claude-md-update | new-template | new-skill}
- **Class:** {A | B} — Class A = content changes (reflection approval sufficient). Class B = operating-model / contract changes (source-of-truth direction, sync semantics, pipeline routing, core contract, command semantics) — REQUIRES linked PRD diff or ADR section before approval. See `$HOME/.claude/skills/evolution/SKILL.md` § Operating-Model Gate.
- **Target:** {file path}
- **What:** {proposed change}
- **Why:** {evidence from this task}
- **Impact:** {low | medium | high}
- **PRD reference (required for Class B):** {path to PRD section authorizing this change, or "N/A" for Class A}
- **Status:** pending approval

## Metrics
- Files changed:
- Lines added/removed:
- Tests added:
- Issues found by QA:
