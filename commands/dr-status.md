---
name: dr-status
description: Check current Datarim task status, progress, and Backlog summary
---

# /dr-status - Check Status

Show current task and Backlog status.

## Path Resolution
**RESOLVE PATH**: Before any read from `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, tell user to run `/dr-init`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

## Display
1. **All active tasks** (from `## Active Tasks` in `activeContext.md`):
   - For each task: Task ID, description, complexity level, current phase, progress
   - Show as numbered list for easy reference
   - If no active tasks → say so explicitly
2. Backlog summary:
   - Pending items
   - In progress
3. Recently completed (from `## Последние завершённые`)
4. Next steps suggestion

## Read
- `datarim/activeContext.md`
- `datarim/tasks.md`
- `datarim/progress.md`
- `datarim/backlog.md`

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
