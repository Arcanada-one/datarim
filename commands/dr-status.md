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
