---
name: dr-quick
description: Lightweight fast-lane for trivial fixes or quick lookups — assign QCK-XXXX, weak-model KB scan, apply the change, short archive. Skips the heavy init→prd→plan pipeline.
---

# /dr-quick — Fast-Lane for Trivial Fixes & Lookups

**Role**: Developer Agent (lightweight)
**Source**: `$HOME/.claude/agents/developer.md`

Use this command for tiny, self-contained edits or quick information lookups that do not merit the full heavyweight pipeline. It deliberately bypasses PRD, planning, design, QA, and compliance stages to minimize overhead.

## Usage

```text
/dr-quick "<short task title>"
```

Note: title defaults to English unless the operator's configured content language is otherwise.

## Stage Header (mandatory)

Every operator-facing response begins with `**{TASK-ID} · {title}**` as the first line before any tool-call narration, per the cta-format skill.

## What happens, step by step

1. Resolve `datarim/` via standard path resolution (walk up; if absent, STOP and tell user to run `/dr-init` — only `/dr-init` creates `datarim/`).
2. Assign the next free `QCK-XXXX` id (scan `tasks.md` + `backlog.md` + `documentation/archive/quick/` for the highest existing QCK number; run an ID-collision probe like `/dr-init`). `QCK` is a universal area-prefix; its archive subdirectory is `quick/`.
3. Append a thin one-liner task line to `tasks.md` and mirror it into `activeContext.md` § Active Tasks. Short English title. `status in_progress`, `priority P3`, `complexity L1` by convention (the fast-lane is for L1-sized work; if the work turns out larger, STOP and recommend `/dr-init` for the full pipeline).
4. Quick KB scan for context: spawn ONE subagent via the Agent tool, using the runtime's CHEAPEST / WEAKEST reasoning tier (vendor-neutral — each runtime resolves its own cheap tier). The subagent does a fast, shallow read of the knowledge base / codebase to locate where the change belongs (or to find what was asked). It returns only the relevant files/context, not a full analysis. This keeps the main (strong) context free and avoids the multi-hour full-analysis path.
5. Apply the fix (for a fix task) or report the located item (for a search task). The actual edit runs in the main context.
6. Write a SHORT archive: `documentation/archive/quick/archive-QCK-XXXX.md` — what was done (1-3 sentences) + files touched + a diff/commit reference. NO reflection, NO evolution proposals, NO compliance report. Flip the `tasks.md` one-liner to status `done`.

## When to use / When not to use

- **Use:** one-file or few-line fixes, typo/config tweaks, quick "where is X / does Y exist" lookups.
- **Not:** anything needing design, multiple files with shared state, security-sensitive logic, or architectural decisions — those go through `/dr-init` and the full pipeline.

## Boundaries

- Skips PRD, plan, design, QA, compliance, and reflection stages.
- QCK archive is intentionally minimal.
- If scope grows mid-task, escalate to `/dr-init`.

## Next Steps (CTA)

After the short archive, emit a CTA block per the cta-format skill. Primary recommendation: the task is done. Alternative: `/dr-init {TASK-ID-or-new}` if it turned out non-trivial. Always include `/dr-status`.

## Stage Snapshot Emission (Mandatory Terminal Step)

After the CTA block, perform snapshot emission per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission, bound for this command: `stage: quick`, `command: /dr-quick`, `captured-by: agent`, `recommended-next` = primary CTA option. Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue. Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library.