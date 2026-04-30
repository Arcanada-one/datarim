---
name: dr-status
description: Check current Datarim task status, progress, and Backlog summary
---

# /dr-status - Check Status

Show current task and Backlog status.

## Path Resolution
**RESOLVE PATH**: Before any read from `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, tell user to run `/dr-init`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

## Display (thin-index schema, TUNE-0071)
1. **All active tasks** — parse one-liner format from `## Active Tasks` in `activeContext.md` (or `## Active` in `tasks.md`):
   - Regex: `^- ([A-Z]{2,10}-[0-9]{4}) · (status) · (P[0-3]) · (L[1-4]) · (.+) → tasks/\1-task-description\.md$`
   - Render numbered list: `{N}. {ID} · {status} · {P}/{L} · {title}`. Max 80-char title (already capped by schema).
   - If no active tasks → say so explicitly.
2. **Backlog summary** — count one-liners by status in `backlog.md`:
   - `pending`: N items
   - `blocked-pending`: N items
   - `cancelled`: N items
3. **Recently completed** — top 5 from `activeContext.md` § «Последние завершённые» (date · ID · title pattern).
4. **Next steps suggestion** — pick highest-priority active task, suggest its current pipeline phase.

For full task content, agent reads `datarim/tasks/{TASK-ID}-task-description.md` on demand. Operational files stay thin.

## Read
- `datarim/activeContext.md` (Active Tasks + Last Updated + Последние завершённые)
- `datarim/tasks.md` (one-liners only — no body to parse)
- `datarim/backlog.md` (one-liners; group by status)
- `datarim/tasks/{TASK-ID}-task-description.md` — only when operator asks for task detail (lazy-load)

## Write
None (read-only)

## Next Steps (CTA)

After printing status, MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`. Since `/dr-status` is read-only, the CTA is purely navigational.

**Routing logic for `/dr-status`:**

- One active task → primary command for that task's current pipeline phase (resolved from `progress.md`/`tasks.md`)
- Multiple active tasks → CTA picks the highest-priority task as primary; surfaces all others in Variant B menu (`**Другие активные задачи:**`)
- No active tasks, backlog has items → primary `/dr-init` (pick from backlog)
- No active tasks, empty backlog → primary `/dr-init "<description>"` (start new task)
- Always include `/dr-help` as escape hatch (command reference)

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B is mandatory for `/dr-status` whenever ≥2 active tasks exist — `/dr-status` is the discovery surface for parallel work.
