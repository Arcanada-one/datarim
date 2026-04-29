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

0.1. **PRE-ARCHIVE GIT CHECK** (MANDATORY):

   **0.1.1 Repo classification.** Every git repo touched by this task is one of:
   - **Workspace repo** (shared, e.g. a workflow-state directory shared by multiple parallel agent sessions): foreign-task-ID hunks are NOT a blocker; only this task's own forgotten hunks (or unattributed hunks) block.
   - **Project repo** (single-agent, e.g. a project's source tree): foreign-task-ID hunks are impossible by construction; treat any uncommitted change as a STOP.

   Default the framework's own state directory and any cross-task workflow store to *workspace*. Default product source trees to *project*. When in doubt, ask the user.

   **0.1.2 Workspace repo check** (per repo classified as shared):
   Run `scripts/pre-archive-check.sh --task-id <CURRENT-TASK-ID> --shared <repo-path>`. The script classifies each modified file's hunks by task ID:
   - `own` — only the current task's ID appears → MUST be committed before archive.
   - `foreign` — only other task IDs (parallel sessions) → leave untouched, NOT a blocker.
   - `mixed` — current + other IDs in the same diff → stage selectively (own only).
   - `unattributed` — no task ID present → require explicit user disposition (default-deny).

   Exit 0 means archive may proceed. Exit 1 means apply recipe 0.1.3 below; STOP if the user declines.

   **0.1.3 Apply recipe — patch staging.** Two equivalent paths:

   <!-- gate:example-only -->
   *Preferred (interactive shell with TTY):*
   ```
   git -C <repo> add -p <workflow-file>
   ```
   Accept only hunks containing the current task ID. Reject foreign hunks.

   *Fallback (non-interactive shell, e.g. AI agent without TTY):* blob-swap recipe.
   ```
   git -C <repo> show HEAD:<file> > /tmp/<file>-mine
   $EDITOR /tmp/<file>-mine                       # apply only your hunk on top of HEAD
   BLOB=$(git -C <repo> hash-object -w /tmp/<file>-mine)
   git -C <repo> update-index --cacheinfo 100644,$BLOB,<file>
   git -C <repo> diff --staged <file>             # verify only your edit staged
   ```

   *Pre-commit retry-tolerant re-verify* (mandatory before `git commit` in either path):
   ```
   git -C <repo> diff --staged --numstat          # verify file-set + line counts
   git -C <repo> log -1 --format=%H               # capture HEAD SHA
   ```
   If file-set / line counts differ from expected delta, or HEAD SHA shifted (parallel session committed in between), rebuild the blob from the new HEAD and re-stage. Do not commit partial state.
   <!-- /gate:example-only -->

   **0.1.4 Cross-task leakage staged-diff audit** (TUNE-0032 / TUNE-0033, preserved):
   After `git add` and before `git commit`, run `git diff --staged --stat` and verify the file-list matches the commit-message scope. Reject the commit if files unrelated to the message scope appear in the staged set; restage selectively. Source: TUNE-0032 — 2 INFRA-0026 files leaked into a TUNE-0032 commit because the staged diff was not inspected before commit.

   **0.1.5 Project repo check** (per repo classified as single-agent):
   Run `scripts/pre-archive-check.sh <project-repo-path>` (legacy mode, unchanged TUNE-0003 behaviour). Exit 1 → STOP and present the 3-way prompt (Commit now / Accept pending / Abort). Applied ≠ committed ≠ canonical.

   **Founding incidents:** VERD-0026 (2026-04-27) — STOP'нулся на foreign hunks от параллельной сессии; project-level rule landed in `~/arcanada/CLAUDE.md` § Multi-Agent Workspace Discipline; TUNE-0044 promotes it to framework runtime. See PRD-TUNE-0044 for the rationale.

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
