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
0. **DETERMINE ARCHIVE AREA**:
   - Extract prefix from task ID (everything before the first `-`, e.g., `INFRA` from `INFRA-0001`)
   - Map prefix to area subdirectory using `$HOME/.claude/skills/datarim-system.md` § Archive Area Mapping
   - If prefix not in mapping → use `general/`
   - Create `documentation/archive/{area}/` directory if it doesn't exist
1. Create archive document with:
   - Task summary
   - Implementation details
   - Reflection insights
2. **BACKLOG UPDATE** (if task existed in backlog):
   - Get current task ID from `datarim/activeContext.md`
   - If the same ID exists in `datarim/backlog.md` (as `in_progress` or `pending`):
     a. **Remove** that entry from `datarim/backlog.md`
     b. **Add** entry to `datarim/backlog-archive.md` under `## Completed` with status `completed`, completion date, and link to archive doc — keeping the same ID
     c. Update Archive Statistics count in `backlog-archive.md`
   - If the task ID does not appear in `backlog.md`: skip this step (task was ad hoc, not from backlog)
3. **FOLLOW-UP TASKS** (from reflection):
   - Read `datarim/reflection/reflection-[task_id].md` for "Next Steps" section
   - If follow-up items exist, ask user: "Add these as new backlog items?"
   - If yes: add each as new `{PREFIX}-XXXX` entry in `datarim/backlog.md` with status `pending`. Choose prefix per Unified Task Numbering (`$HOME/.claude/skills/datarim-system.md`) — project or area prefix relevant to the follow-up item
4. **UPDATE ARCHIVED TASKS TABLE**: Add a row to the `## Archived Tasks` table in `datarim/tasks.md`:
   ```
   | {task_id} | {title} | {today's date} | `documentation/archive/{area}/archive-{task_id}.md` |
   ```
5. Reset `activeContext.md`
6. Clear completed task from Active Tasks section of `tasks.md` (keep Archived Tasks table)

## Read
- `datarim/tasks.md`
- `datarim/reflection/reflection-[task_id].md`
- `datarim/creative/*.md` (Level 3-4)
- `datarim/backlog.md` (to find and remove completed/cancelled item)
- `datarim/backlog-archive.md` (to append completed/cancelled item)
- `$HOME/.claude/skills/datarim-system.md` (Archive Area Mapping)

## Write
- `documentation/archive/[area]/archive-[task_id].md`
- `datarim/backlog.md` (if applicable)
- `datarim/backlog-archive.md` (if applicable)
- `datarim/tasks.md` (clear)
- `datarim/activeContext.md` (reset)

## Cancellation Mode

If user says "cancel task" or "cancel {TASK-ID}":
1. Get task ID from `datarim/activeContext.md` (or from user argument)
2. **Remove** the entry from `datarim/backlog.md` (if present)
3. **Add** entry to `datarim/backlog-archive.md` under `## Cancelled` with status `cancelled`, date, and reason — keeping the same ID
4. Reset `activeContext.md`
5. Clear task from `tasks.md`
6. Do NOT create archive document (task was not completed)

## Next
- Ready for new task → `/dr-init`
- Knowledge base grown since last maintenance? → Suggest `/dr-dream` (if >5 documents created since last dream run)
