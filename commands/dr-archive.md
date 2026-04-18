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

0. **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Resolve which task is being archived (from argument or disambiguation). Use the resolved task ID for all subsequent steps.

0.1. **PRE-ARCHIVE CLEAN-GIT CHECK** (MANDATORY):
   - For every git repository touched by this task (arcanada workspace + any nested project repos like `Projects/Datarim/code/datarim/`), run `git status --porcelain`.
   - If any repo has uncommitted changes, STOP and present the list to the user with three options:
     a. **Commit now** (proceed with archive after commits land).
     b. **Explicitly accept pending state** (record the reason in the archive document's "Known Outstanding State" section).
     c. **Abort archive** (return to `/dr-do` or fix manually).
   - Do NOT archive over a dirty working tree silently. Applied ≠ committed ≠ canonical — see TUNE-0003 reflection for the governance rationale.

0.5. **REFLECT** (MANDATORY, non-skippable):
   - Load `$HOME/.claude/skills/reflecting.md`.
   - Execute the reflect workflow per that skill:
     a. Create `datarim/reflection/reflection-[task_id].md`.
     b. Generate evolution proposals (categories: skill-update, agent-update, claude-md-update, new-template, new-skill).
     c. Classify Class A / Class B per `skills/evolution.md`.
     d. Present Class A for approval; hold Class B (require PRD update before apply).
     e. Apply approved Class A to runtime; log in `datarim/docs/evolution-log.md`.
     f. Run health-metrics check; suggest `/dr-optimize` if thresholds exceeded (no auto-run).
     g. Note follow-up tasks for Step 4 consumption.
   - Step CANNOT be skipped. No `--no-reflect` flag exists.
   - On failure (skill load error / user rejects Class A): STOP archive; do NOT proceed to Step 1. Archive is idempotent — re-running re-enters Step 0.5.
   - Historical: prior to Datarim v1.10.0 (TUNE-0013), this ran as a separate `/dr-reflect` command; consolidated here because an "optional mandatory gate" is the defect.

1. **DETERMINE ARCHIVE AREA**:
   - Extract prefix from task ID (everything before the first `-`, e.g., `INFRA` from `INFRA-0001`)
   - Map prefix to area subdirectory using `$HOME/.claude/skills/datarim-system.md` § Archive Area Mapping
   - If prefix not in mapping → use `general/`
   - Create `documentation/archive/{area}/` directory if it doesn't exist
2. Create archive document with:
   - Task summary
   - Implementation details
   - Reflection insights
   - **Known Loss Verification Gate (MANDATORY when archive will include any "Known Loss" / "Unrecoverable" / "Content lost" statement):**
     Before recording that any file, section, decision, or piece of work is permanently lost, run the Disaster Recovery Checklist from `$HOME/.claude/skills/evolution.md` § Disaster Recovery for Lost Runtime Files. Record in the archive document which channels were checked (grep reflections by filename, compacted session context, cross-references, git history of consumer projects, external backups) and what each returned. If the checklist takes >30 minutes, defer the archive, open a follow-up recovery task, do not record the loss yet. Only after all 5 channels are exhausted may a loss claim enter the archive. Rationale: TUNE-0003 archive recorded 4 files as "text reconstruction is not possible" after 0 minutes of discovery; TUNE-0011 recovered 100% of them in 20 minutes using channels 1-3.
3. **BACKLOG UPDATE** (if task existed in backlog):
   - Use the resolved task ID from Step 0
   - If the same ID exists in `datarim/backlog.md` (as `in_progress` or `pending`):
     a. **Remove** that entry from `datarim/backlog.md`
     b. **Add** entry to `datarim/backlog-archive.md` under `## Completed` with status `completed`, completion date, and link to archive doc — keeping the same ID
     c. Update Archive Statistics count in `backlog-archive.md`
   - If the task ID does not appear in `backlog.md`: skip this step (task was ad hoc, not from backlog)
4. **FOLLOW-UP TASKS** (from reflection):
   - Read `datarim/reflection/reflection-[task_id].md` for "Next Steps" section
   - If follow-up items exist, ask user: "Add these as new backlog items?"
   - If yes: add each as new `{PREFIX}-XXXX` entry in `datarim/backlog.md` with status `pending`. Choose prefix per Unified Task Numbering (`$HOME/.claude/skills/datarim-system.md`) — project or area prefix relevant to the follow-up item
5. **UPDATE ARCHIVED TASKS TABLE**: Add a row to the `## Archived Tasks` table in `datarim/tasks.md`:
   ```
   | {task_id} | {title} | {today's date} | `documentation/archive/{area}/archive-{task_id}.md` |
   ```
6. **Remove** the archived task from `## Active Tasks` in `activeContext.md`. Keep other active tasks. Prepend the newly archived task to `## Последние завершённые`. Do NOT reset the entire file. See `$HOME/.claude/skills/datarim-system.md` § activeContext.md Write Rules.
7. Clear the archived task from Active Tasks section of `tasks.md` (keep Archived Tasks table and other active tasks)

## Read
- `datarim/tasks.md`
- `datarim/reflection/reflection-[task_id].md` (written by Step 0.5)
- `datarim/creative/*.md` (Level 3-4)
- `datarim/backlog.md` (to find and remove completed/cancelled item)
- `datarim/backlog-archive.md` (to append completed/cancelled item)
- `$HOME/.claude/skills/datarim-system.md` (Archive Area Mapping)
- `$HOME/.claude/skills/reflecting.md` (loaded by Step 0.5)
- `$HOME/.claude/skills/evolution.md` (loaded by Step 0.5 for Class A/B gate)

## Write
- `documentation/archive/[area]/archive-[task_id].md`
- `datarim/backlog.md` (if applicable)
- `datarim/backlog-archive.md` (if applicable)
- `datarim/tasks.md` (clear)
- `datarim/activeContext.md` (reset)

## Cancellation Mode

If user says "cancel task" or "cancel {TASK-ID}":
1. Resolve task ID using Task Resolution Rule (argument or disambiguation).
2. **Remove** the entry from `datarim/backlog.md` (if present)
3. **Add** entry to `datarim/backlog-archive.md` under `## Cancelled` with status `cancelled`, date, and reason — keeping the same ID
4. **Remove** the cancelled task from `## Active Tasks` in `activeContext.md` (keep other active tasks)
5. Clear task from `tasks.md`
6. Do NOT create archive document (task was not completed)

## Next
- Ready for new task → `/dr-init`
- Knowledge base grown since last maintenance? → Suggest `/dr-dream` (if >5 documents created since last dream run)
