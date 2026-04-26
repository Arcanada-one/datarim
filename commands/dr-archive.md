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
   - **Staged-diff audit (per commit):** after `git add` and before `git commit`, run `git diff --staged --stat` and visually verify the file list matches the commit-message scope. Reject the commit if files unrelated to the message scope appear in the staged set; restage selectively. Source: TUNE-0032 — 2 INFRA-0026 files (`skills/file-sync-config.md`, `templates/cli-conflict-resolver-prompt.md`) leaked into the TUNE-0032 commit despite an explicit `git add` path-list, undetected because the staged diff was not inspected before commit.
   - **Workspace cross-task leakage detection (proactive):** when running clean-git check, examine each modified `datarim/` workflow file (`tasks.md`, `backlog.md`, `progress.md`, `activeContext.md`) and grep for task IDs other than the archiving task. If foreign task IDs appear in the diff (e.g. `TRANS-0015`, `VERD-0010`) → flag those changes as "out-of-scope, exclude from archive commit". Their state belongs to an unrelated session and must not be bundled. Source: TUNE-0033 — workspace `datarim/{tasks,backlog,progress,activeContext}.md` carried 100+ uncommitted lines from TRANS-0015 / VERD-0010 / LTM-0004 prior sessions; staged-diff audit caught the leak only at commit time; proactive task-ID mapping at Step 0.1 prevents the round-trip.

0.5. **REFLECT** (MANDATORY, non-skippable):
   - Load `$HOME/.claude/skills/reflecting.md`.
   - Execute the reflect workflow per that skill:
     a. Create `datarim/reflection/reflection-[task_id].md`.
     b. Generate evolution proposals (categories: skill-update, agent-update, claude-md-update, new-template, new-skill).
     c. Classify Class A / Class B per `skills/evolution.md`.
     d. Present Class A for approval; hold Class B (require PRD update before apply).
     e. Apply approved Class A to runtime (stack-agnostic gate MUST PASS per `$HOME/.claude/skills/evolution/stack-agnostic-gate.md`; gate FAIL → reject the proposal and ask user to either reword stack-neutral or relocate to project's `CLAUDE.md`); log applied changes in `datarim/docs/evolution-log.md`.
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
   - **Pruning:** After adding the new entry, if `## Последние завершённые` has more than 10 entries, remove the oldest entries (bottom of list) to keep exactly 10.
7. **REMOVE TASK BODY from tasks.md**:
   - Delete the ENTIRE task entry (from `### {TASK-ID}` to the next `###` or `##` header) from `## Active Tasks` section.
   - Do NOT preserve task content in HTML comments (`<!-- -->`). The archive file in `documentation/archive/` IS the permanent record.
   - If the task has an associated plan file (`datarim/plans/{TASK-ID}-plan.md`), delete that file too.
   - Keep the `## Archived Tasks` table and all other active tasks intact.

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

## Next Steps (CTA)

After archive, the planner agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`. After archiving, the just-archived task is removed from `## Active Tasks`; CTA reflects the new state of activeContext.

**Routing logic for `/dr-archive`:**

- Archive completed, other active tasks remain → primary `/dr-continue` (resume the next active task) + alternative `/dr-status`
- Archive completed, no other active tasks → primary `/dr-init` (start new work) + alternative "pick from backlog"
- Knowledge base grew >5 docs since last maintenance → alternative `/dr-dream` (housekeeping)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format. If multiple tasks remain active after this archive, render Variant B menu (`**Другие активные задачи:**`).
