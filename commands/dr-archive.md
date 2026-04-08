---
name: dr-archive
description: Archive completed task with comprehensive documentation and Datarim updates
disable-model-invocation: true
---

# /dr-archive - Archive Task

Complete and archive current task.

## Path Resolution
**RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

## Steps
1. Create archive document with:
   - Task summary
   - Implementation details
   - Reflection insights
2. Update Backlog (if from Backlog)
3. Reset `activeContext.md`
4. Clear `tasks.md`

## Read
- `datarim/tasks.md`
- `datarim/reflection/reflection-[task_id].md`
- `datarim/creative/*.md` (Level 3-4)

## Write
- `datarim/archive/archive-[task_id].md`
- `datarim/backlog.md` (if applicable)
- `datarim/backlog-archive.md` (if applicable)
- `datarim/tasks.md` (clear)
- `datarim/activeContext.md` (reset)

## Next
Ready for new task → `/dr-init`
