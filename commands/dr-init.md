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
3.  **ACTION**:
    - Analyze the user request.
    - Determine complexity level (1-4).
    - **Context Gathering**: For complex tasks, ensure context is gathered (via `/dr-prd`) before planning.
    - **If new project/service**: Load `$HOME/.claude/skills/tech-stack.md` and identify required stack.
    - Create/Update `datarim/tasks.md` with new task.
    - Update `datarim/activeContext.md`.
4.  **OUTPUT**: Initialized task structure (including tech stack if applicable).

## Next Steps
- Level 1? → `/dr-do`
- Level 2+? → `/dr-plan`
