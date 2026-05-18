---
name: dr-init
description: Initialize a new Datarim task or scaffold a new project. Auto-detects intent from prompt context.
---

# /dr-init — Initialize New Task or Project

> **Contract.** Initialisation is the only command that may create `datarim/`, wires prefix → archive-subdir mapping, and selects task IDs that propagate through the rest of the pipeline. The structural compliance probe (Step 2.4 — `datarim-doctor.sh --quiet`), the workspace cross-task hygiene check (Step 2.5), and the PRD-waiver gate are enforced in code, independent of how the command is invoked. Prefer the canonical slash form (`/dr-init {DESCRIPTION}`) over manually creating `datarim/` artefacts: the slash command threads through every guard described in this file; ad-hoc paths skip them.

**Role**: Planner Agent (Initial)
**Source**: `$HOME/.claude/agents/planner.md`

## Instructions
0.  **INTENT DETECTION** — Determine whether the user wants to create a **project** or a **task**:
    - Scan the user's input for project creation signals:
      - English keywords: "create project", "new project", "init project", "scaffold project", "setup project"
      - Russian keywords: "создай проект", "новый проект", "инициализируй проект", "создать проект"
      - Pattern: `/dr-init create project "Name"`
      - Pattern: `/dr-init new project for <description>`
    - **If project intent detected:**
      a. Load `$HOME/.claude/skills/project-init.md` and follow its scaffolding flow.
      b. **EXIT** — do not continue to the task flow below.
    - **If NO project intent detected:**
      → Continue to Step 1 (standard task flow, unchanged).

1.  **LOAD**: Read `$HOME/.claude/agents/planner.md` and adopt that persona.
2.  **RESOLVE PATH**: This is the ONLY command that may create `datarim/`. Resolve the correct location:
    - Find the **top-level git root** (`git rev-parse --show-toplevel`).
    - If the project uses submodules, use the **outermost** repo root (e.g., `local-env/`, not `aio-v2/`).
    - Create `datarim/` there ONLY if it does not already exist.
    - If creating for the first time:
      a. Create `backlog.md` and `backlog-archive.md` from templates at `$HOME/.claude/templates/backlog-template.md` and `$HOME/.claude/templates/backlog-archive-template.md`.
      b. Create `documentation/archive/` directory (for long-term task archives).
      c. If `.gitignore` exists and does not contain `datarim/` → append `datarim/` to it.
      d. If `.gitignore` does not exist → ask user: "Create `.gitignore` with `datarim/`? (recommended — keeps workflow state local)"

2.4. **STRUCTURAL COMPLIANCE CHECK** (runs only when `datarim/` already exists — skip on first-time creation in Step 2):
    - Probe: `scripts/datarim-doctor.sh --quiet --root="$DATARIM_ROOT"` (exit code only).
    - **exit 0** → silent, continue to Step 2.5.
    - **exit 1** (non-compliant findings):
      - Print summary: `"datarim/ structure non-compliant: {N} findings"` (re-run without `--quiet` to surface counts).
      - Interactive (TTY, `[ -t 0 ]`) → prompt: `"Run /dr-doctor --fix? [Y/n]"`. Default Y.
        - Y → invoke `/dr-doctor --fix` (or directly `scripts/datarim-doctor.sh --fix --root="$DATARIM_ROOT"`), then continue.
        - n → print warning, continue with non-compliance (operator's call; `/dr-archive` schema gate will block later).
      - Non-tty (`! [ -t 0 ]`) → skip prompt, print warning, continue.
    - **exit 2** (migration error from a prior run) → print error, ABORT `/dr-init`. Operator inspects state manually.
    - **exit 3** (concurrent invocation, lock held) → wait briefly and retry once; if still held → ABORT.
    - **exit 4** (path-traversal violation in operational files) → print error, ABORT — security violation, do NOT continue.
    - This check is the self-heal entry point for the thin-index schema. See `skills/datarim-doctor.md` for the canonical contract.

2.5. **WORKSPACE CROSS-TASK HYGIENE CHECK** (advisory, non-blocking):
    - After path resolution, run `git status --porcelain datarim/tasks.md datarim/activeContext.md datarim/backlog.md datarim/progress.md` (those that exist).
    - Grep their pending diffs for foreign task IDs (anything matching `[A-Z]+-[0-9]{4}` other than the new task being initialised).
    - If foreign IDs are found, emit a single-line advisory: `"Workspace datarim/* carries pending state for {N} other tasks: {ID1, ID2, ...}. Consider /dr-archive or commit before /dr-init."`
    - **Non-blocking** — operator proceeds at will. Skip silently if the workspace is clean or no `datarim/*.md` exist yet.
    - The staged-diff audit at `/dr-archive` already catches the tangle but only after the carry-over has already cost a session; surfacing it at `/dr-init` lets the operator clean state proactively.

2.5b. **TOPIC OVERLAP ADVISORY** (advisory, non-blocking; framework v2.7.0+):
    - Catches topic-overlap with **pending backlog items** — orthogonal to Step 2.5, which catches foreign task IDs in pending diffs. Recurrence motivating this gate: two backlog IDs spawned for one deliverable when an earlier pending item escaped notice during fresh `/dr-init`.
    - Skip silently when any of the following holds:
      - `datarim/backlog.md` absent or empty of `pending` items.
      - `python3` not on `PATH` (echo single-line `"python3 not available — topic-overlap check skipped"` and continue; framework dependency floor stays Bash-only).
      - The runtime root is missing `dev-tools/check-topic-overlap.py` (older install, advisory deferred until upgrade).
    - Otherwise invoke:
      ```bash
      printf '%s\n' "$USER_TASK_DESCRIPTION" | \
        python3 "$DATARIM_RUNTIME/dev-tools/check-topic-overlap.py" \
          --task-description - \
          --backlog "$DATARIM_ROOT/backlog.md" \
          --top-n 5 --min-overlap 2
      ```
      `$DATARIM_RUNTIME` is the framework code root (`code/datarim` in the framework repo, `~/.claude` after install).
    - Stream stdout straight to the operator. The script is **exit 0 by contract** — exit code is ignored even on parse anomalies.
    - In non-tty / CI runs (`DATARIM_NONINTERACTIVE=1` or `! [ -t 0 ]`): capture stdout into the step report, never prompt.
    - When the advisory surfaces matches, operator chooses: `duplicate` (abort + `/dr-init {EXISTING-ID}`), `refine-scope` (narrow new task to avoid collision), or `orthogonal` (continue — overlap is incidental). Default on no operator input: continue.
    - Performance contract: completes ≤300 ms on a 500-item backlog (regression-gated by `tests/dr-init-topic-overlap-latency.bats`); false-positive rate <10% on a 30-item orthogonal corpus (`tests/dr-init-topic-overlap-fp-budget.bats`).

3.  **CHECK BACKLOG**: If `datarim/backlog.md` exists and contains pending items:
    - Display pending items as a numbered list (ID, title, priority, complexity).
    - **If user provided a `BACKLOG-XXXX` ID**: Select that item directly.
    - **If user said "pick from backlog"** or gave no task description: Show list and ask which to start.
    - **When selecting a backlog item**:
      a. Change its status from `pending` to `in_progress` in `backlog.md`.
      b. Use its description, priority, complexity, and acceptance criteria as starting context.
      c. **Use the backlog item's existing ID as the task ID** (do NOT create a new one). The ID stays the same across lifecycle per Unified Task Numbering.
    - **If backlog is empty** or user provided a new task description: Proceed to step 4.
4.  **ACTION**:
    - Analyze the user request (or backlog item context from step 3).
    - Determine complexity level (1-4). If from backlog, use the item's complexity as starting estimate.
    - **Determine Task ID** (if NOT from backlog): select prefix per Unified Task Numbering (`$HOME/.claude/skills/datarim-system.md`) — project prefix first, then area prefix, `TASK` as fallback. Scan existing tasks for next sequential number.
    - **Context Gathering**: For complex tasks, ensure context is gathered (via `/dr-prd`) before planning.
    - **PRD Waiver Check** (Level 3-4 only): If no PRD exists for this task (check `datarim/prd/PRD-{task-id}*.md` and parent PRD within 30 days), prompt: "No PRD found for this L3+ task. Options: (a) Run `/dr-prd` first, (b) State waiver reason (will be recorded as `**PRD waived:**` in tasks.md)." If user chooses (b), record the waiver in the task's Overview section. Retroactive-only enforcement is insufficient — the prompt at `/dr-init` is the canonical gate.
    - **If new project/service**: Load `$HOME/.claude/skills/tech-stack.md` and identify required stack.
    - Create/Update `datarim/tasks.md` with new task.
    - **Append** new task to `## Active Tasks` in `datarim/activeContext.md`. Do NOT remove existing active tasks. If `activeContext.md` uses legacy format (`**Current Task:**` single line), convert to `## Active Tasks` list first. See `$HOME/.claude/skills/datarim-system.md` § activeContext.md Write Rules.
4.6. **WRITE INIT-TASK FILE** (mandatory, F1 contract — see `$HOME/.claude/skills/init-task-persistence.md`):
    - Compute `INIT_TASK_FILE="datarim/tasks/{TASK-ID}-init-task.md"`.
    - Determine the source flow:
      - **Operator prompt flow** (default): the `ARGUMENTS` variable (the text the operator typed after `/dr-init`) becomes the body of `## Operator brief (verbatim)`. Frontmatter `source: /dr-init`.
      - **Backlog selection flow** (the task was picked from `backlog.md` in Step 3): copy the matched backlog item's description block verbatim into `## Operator brief (verbatim)`. Frontmatter `source: backlog`, `source_backlog_ref: backlog.md#{TASK-ID}`.
    - Write the file with the canonical 8-field frontmatter (`task_id`, `artifact: init-task`, `schema_version: 1`, `captured_at`, `captured_by: /dr-init`, `operator`, `status: canonical`, `source`) + two mandatory headings: `## Operator brief (verbatim)` and `## Append-log (operator amendments)` (empty placeholder `_(пусто на момент создания)_`). Optional `## Source command` block above the brief is recommended when the exact invocation differs from `ARGUMENTS` raw text.
    - Probe: `dev-tools/check-init-task-presence.sh --task {TASK-ID} --root "$DATARIM_ROOT"` (where `$DATARIM_ROOT` is the parent of `datarim/`). Exit 0 = OK; non-zero = print warning and continue (operator may amend manually).
    - Skip silently when re-running `/dr-init` on an existing backlog ID whose init-task already exists — preserve the verbatim history.

5.  **SUBTASK BACKLOG** (Level 3-4 only):
    - If analysis reveals distinct subtasks or phases, present them to user:
      "This task has N identifiable subtasks. Add them to backlog for independent tracking?"
    - If approved: create entries in `datarim/backlog.md` using appropriate project/area prefix per Unified Task Numbering (NOT `BACKLOG-XXXX`). Subtasks of a project task typically share its project prefix.
6.  **OUTPUT**: Initialized task structure (including tech stack if applicable).

## Reusable Templates

- `templates/task-template.md` — minimal Implementation-Plan scaffold (`Overview` / `Architecture Impact` / `Implementation Steps` / `Test Plan` / `Rollback Strategy` / `Validation Checklist`). Use when bootstrapping `datarim/tasks/{TASK-ID}-task-description.md` for L1-L2 tasks where the heavier `prd-template.md` would be overkill.

## Next Steps (CTA)

After completing initialization, the planner agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-init`:**

- New L1 task → primary `/dr-do {TASK-ID}` (single-file fix, ≤50 LoC)
- New L2 task → primary `/dr-plan {TASK-ID}` (planning before code)
- New L3-4 task without PRD → primary `/dr-prd {TASK-ID}` (PRD obligatory unless waiver)
- New L3-4 task with parent PRD <30 days → alternative `/dr-plan {TASK-ID}` (waiver path)
- Backlog had pending items shown → alternative `/dr-init {BACKLOG-ID}` for any other listed item
- Always include `/dr-status` as escape hatch

The CTA block MUST: (a) include resolved task ID, (b) mark exactly one `**рекомендуется**`, (c) list ≤5 numbered options, (d) be wrapped in `---` HR. If >1 active tasks in `datarim/activeContext.md`, append `**Другие активные задачи:**` menu (Variant B).
