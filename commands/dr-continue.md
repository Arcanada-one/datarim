---
name: dr-continue
description: Resume work on current task from last checkpoint with context awareness
---

# /dr-continue - Resume Task

Continue from where you left off.

## Steps
1. **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
2. **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps. If >1 active tasks, show all with their current phase and ask which to resume.
3. Read current state for the resolved task
4. Determine phase (INIT/PLAN/DESIGN/DO/REFLECT)
5. Show context summary
6. Resume appropriate action

## Read
- `datarim/activeContext.md`
- `datarim/tasks.md`
- `datarim/progress.md`
- `datarim/backlog.md` (for routing when no active task)

## Write
Depends on current phase

## Routing
- No active task → check `datarim/backlog.md` for pending items:
  - If pending items exist → display them and suggest `/dr-init` with backlog selection
  - If no pending items → suggest `/dr-init` with new task
- Multiple active tasks → show all with phases, ask which to resume
- In PLAN → continue planning
- In DO → continue implementation
- Ready for ARCHIVE → suggest `/dr-archive`

## Next Steps (CTA)

After resolving the current phase, the planner/architect/developer agent (whichever owns the resumed phase) MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-continue`:**

- Resumed in PLAN phase → primary `/dr-plan {TASK-ID}` (continue planning)
- Resumed in DESIGN phase → primary `/dr-design {TASK-ID}`
- Resumed in DO phase → primary `/dr-do {TASK-ID}`
- Ready for QA / archive → primary `/dr-qa {TASK-ID}` or `/dr-archive {TASK-ID}` per pipeline
- No active tasks but backlog has items → primary `/dr-init` (pick from backlog)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format. If >1 active tasks, the entire `## Active Tasks` list is the menu (Variant B fully expanded).
