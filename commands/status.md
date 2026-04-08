---
name: status
description: Check current Datarim task status, progress, and Backlog summary
---

# /status - Check Status

Show current task and Backlog status.

## Path Resolution
**RESOLVE PATH**: Before any read from `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, tell user to run `/init`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

## Display
1. Current task info:
   - Task ID & description
   - Complexity level
   - Current phase
   - Progress
2. Backlog summary:
   - Pending items
   - In progress
3. Next steps suggestion

## Read
- `datarim/activeContext.md`
- `datarim/tasks.md`
- `datarim/progress.md`
- `datarim/backlog.md`

## Write
None (read-only)
