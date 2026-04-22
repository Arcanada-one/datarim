---
name: dr-init
description: Initialize a new Datarim task or scaffold a new project. Auto-detects intent from prompt context.
disable-model-invocation: true
---

# /dr-init - Initialize New Task or Project

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
3.  **CHECK BACKLOG**: If `datarim/backlog.md` exists and contains pending items:
    - Display pending items as a numbered list (ID, title, priority, complexity).
    - **If user provided a `BACKLOG-XXXX` ID**: Select that item directly.
    - **If user said "pick from backlog"** or gave no task description: Show list and ask which to start.
    - **When selecting a backlog item**:
      a. Change its status from `pending` to `in_progress` in `backlog.md`.
      b. Use its description, priority, complexity, and acceptance criteria as starting context.
      c. **Use the backlog item's existing ID as the task ID** (do NOT create a new one). Example: `INFRA-0004` in backlog → `INFRA-0004` as active task. The ID stays the same across lifecycle per Unified Task Numbering.
    - **If backlog is empty** or user provided a new task description: Proceed to step 4.
4.  **ACTION**:
    - Analyze the user request (or backlog item context from step 3).
    - Determine complexity level (1-4). If from backlog, use the item's complexity as starting estimate.
    - **Determine Task ID** (if NOT from backlog): select prefix per Unified Task Numbering (`$HOME/.claude/skills/datarim-system.md`) — project prefix first, then area prefix, `TASK` as fallback. Scan existing tasks for next sequential number.
    - **Context Gathering**: For complex tasks, ensure context is gathered (via `/dr-prd`) before planning.
    - **PRD Waiver Check** (Level 3-4 only): If no PRD exists for this task (check `datarim/prd/PRD-{task-id}*.md` and parent PRD within 30 days), prompt: "No PRD found for this L3+ task. Options: (a) Run `/dr-prd` first, (b) State waiver reason (will be recorded as `**PRD waived:**` in tasks.md)." If user chooses (b), record the waiver in the task's Overview section. Source: TUNE-0009 audit found retroactive-only enforcement insufficient.
    - **If new project/service**: Load `$HOME/.claude/skills/tech-stack.md` and identify required stack.
    - Create/Update `datarim/tasks.md` with new task.
    - **Append** new task to `## Active Tasks` in `datarim/activeContext.md`. Do NOT remove existing active tasks. If `activeContext.md` uses legacy format (`**Current Task:**` single line), convert to `## Active Tasks` list first. See `$HOME/.claude/skills/datarim-system.md` § activeContext.md Write Rules.
5.  **SUBTASK BACKLOG** (Level 3-4 only):
    - If analysis reveals distinct subtasks or phases, present them to user:
      "This task has N identifiable subtasks. Add them to backlog for independent tracking?"
    - If approved: create entries in `datarim/backlog.md` using appropriate project/area prefix per Unified Task Numbering (NOT `BACKLOG-XXXX`). Subtasks of a project task typically share its project prefix.
6.  **OUTPUT**: Initialized task structure (including tech stack if applicable).

## Next Steps
- Level 1? → `/dr-do`
- Level 2+? → `/dr-plan`
- No task specified and backlog has pending items? → Show backlog for selection
