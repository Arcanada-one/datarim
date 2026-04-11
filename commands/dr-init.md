---
name: dr-init
description: Initialize a new Datarim task with complexity detection and automatic task numbering
disable-model-invocation: true
---

# /dr-init - Initialize New Task

**Role**: Planner Agent (Initial)
**Source**: `$HOME/.claude/agents/planner.md`

## Instructions
1.  **LOAD**: Read `$HOME/.claude/agents/planner.md` and adopt that persona.
2.  **RESOLVE PATH**: This is the ONLY command that may create `datarim/`. Resolve the correct location:
    - Find the **top-level git root** (`git rev-parse --show-toplevel`).
    - If the project uses submodules, use the **outermost** repo root (e.g., `local-env/`, not `aio-v2/`).
    - Create `datarim/` there ONLY if it does not already exist.
    - If creating for the first time, also create `backlog.md` and `backlog-archive.md` from templates at `$HOME/.claude/templates/backlog-template.md` and `$HOME/.claude/templates/backlog-archive-template.md`.
3.  **CHECK BACKLOG**: If `datarim/backlog.md` exists and contains pending items:
    - Display pending items as a numbered list (ID, title, priority, complexity).
    - **If user provided a `BACKLOG-XXXX` ID**: Select that item directly.
    - **If user said "pick from backlog"** or gave no task description: Show list and ask which to start.
    - **When selecting a backlog item**:
      a. Change its status from `pending` to `in_progress` in `backlog.md`.
      b. Use its description, priority, complexity, and acceptance criteria as starting context.
      c. Create a new task with `TASK-XXXX` ID. Record `Source: BACKLOG-XXXX` in `tasks.md`.
    - **If backlog is empty** or user provided a new task description: Proceed to step 4.
4.  **ACTION**:
    - Analyze the user request (or backlog item context from step 3).
    - Determine complexity level (1-4). If from backlog, use the item's complexity as starting estimate.
    - **Context Gathering**: For complex tasks, ensure context is gathered (via `/dr-prd`) before planning.
    - **If new project/service**: Load `$HOME/.claude/skills/tech-stack.md` and identify required stack.
    - Create/Update `datarim/tasks.md` with new task.
    - Update `datarim/activeContext.md`.
5.  **OUTPUT**: Initialized task structure (including tech stack if applicable).

## Next Steps
- Level 1? → `/dr-do`
- Level 2+? → `/dr-plan`
- No task specified and backlog has pending items? → Show backlog for selection
