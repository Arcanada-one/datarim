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
2. **BACKLOG UPDATE** (if task originated from backlog):
   - Read `datarim/tasks.md` to find `Source: BACKLOG-XXXX`
   - If found:
     a. **Remove** the BACKLOG-XXXX entry from `datarim/backlog.md`
     b. **Add** entry to `datarim/backlog-archive.md` under `## Completed` with status `completed`, completion date, and link to archive doc
     c. Update Archive Statistics count in `backlog-archive.md`
   - If task was NOT from backlog: skip this step
3. **FOLLOW-UP TASKS** (from reflection):
   - Read `datarim/reflection/reflection-[task_id].md` for "Next Steps" section
   - If follow-up items exist, ask user: "Add these as new backlog items?"
   - If yes: add each as new `BACKLOG-XXXX` entry in `datarim/backlog.md` with status `pending`
4. Reset `activeContext.md`
5. Clear completed task from `tasks.md`

## Read
- `datarim/tasks.md`
- `datarim/reflection/reflection-[task_id].md`
- `datarim/creative/*.md` (Level 3-4)
- `datarim/backlog.md` (to find and remove completed/cancelled item)
- `datarim/backlog-archive.md` (to append completed/cancelled item)

## Write
- `datarim/archive/archive-[task_id].md`
- `datarim/backlog.md` (if applicable)
- `datarim/backlog-archive.md` (if applicable)
- `datarim/tasks.md` (clear)
- `datarim/activeContext.md` (reset)

## Cancellation Mode

If user says "cancel task" or "cancel BACKLOG-XXXX":
1. Read `datarim/tasks.md` for `Source: BACKLOG-XXXX`
2. **Remove** the entry from `datarim/backlog.md`
3. **Add** entry to `datarim/backlog-archive.md` under `## Cancelled` with status `cancelled`, date, and reason
4. Reset `activeContext.md`
5. Clear task from `tasks.md`
6. Do NOT create archive document (task was not completed)

## Next
- Ready for new task → `/dr-init`
- Knowledge base grown since last maintenance? → Suggest `/dr-dream` (if >5 documents created since last dream run)
