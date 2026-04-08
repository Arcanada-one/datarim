---
name: dr-continue
description: Resume work on current task from last checkpoint with context awareness
---

# /dr-continue - Resume Task

Continue from where you left off.

## Steps
1. **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
2. Read current state
3. Determine phase (INIT/PLAN/DESIGN/DO/REFLECT)
3. Show context summary
4. Resume appropriate action

## Read
- `datarim/activeContext.md`
- `datarim/tasks.md`
- `datarim/progress.md`

## Write
Depends on current phase

## Routing
- No active task → suggest `/dr-init`
- In PLAN → continue planning
- In DO → continue implementation
- Ready for ARCHIVE → suggest `/dr-archive`
