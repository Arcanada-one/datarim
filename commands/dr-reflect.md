---
name: dr-reflect
description: Review completed task and create reflection document with lessons learned
---

# /dr-reflect - Review & Quality Mode

**Role**: Reviewer Agent
**Source**: `$HOME/.claude/agents/reviewer.md`

## Instructions
1.  **LOAD**: Read `$HOME/.claude/agents/reviewer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **SKILL**: Read `$HOME/.claude/skills/security.md` and `$HOME/.claude/skills/testing.md`.
4.  **CONTEXT**: Read `datarim/tasks.md` and `datarim/style-guide.md`.
4.  **ACTION**:
    - Review changes against Definition of Done.
    - Verify tests pass.
    - Check for security vulnerabilities.
    - Create reflection document using `$HOME/.claude/templates/reflection-template.md` (fallback to `datarim/templates/reflection-template.md` only if project provides a custom template).
5.  **EVOLUTION**:
    - Load `$HOME/.claude/skills/evolution.md`.
    - Analyze: what worked well? what was inefficient? any missing skills/patterns?
    - Generate evolution proposals (categories: `skill-update`, `agent-update`, `claude-md-update`, `new-template`, `new-skill`).
    - **Classify each proposal as Class A or Class B** per `evolution.md` § "Class A vs Class B — Operating-Model Gate". Class A = content changes (approval-ready). Class B = operating-model / contract changes (source-of-truth direction, sync semantics, pipeline routing, core contract, command semantics). Class B proposals **must not be presented for user approval** until a PRD update (or project-level contract equivalent) is drafted; pause and request the PRD draft instead.
    - Present Class A proposals to user for approval. Hold Class B until PRD is updated, then re-present.
    - Log approved changes in `datarim/docs/evolution-log.md`.
6.  **HEALTH CHECK**:
    - Count total skills, agents, commands in the active scope.
    - Check against Health Metrics thresholds (see `evolution.md`).
    - If any threshold is exceeded, suggest: "Framework may benefit from optimization. Run `/dr-optimize` to audit and clean up."
    - This is a suggestion only — do not run optimization automatically.
7.  **FOLLOW-UP TASKS**:
    - Review the "Next Steps" section of the reflection document.
    - If follow-up tasks are identified, note them for `/dr-archive` to add to backlog.
    - Do NOT add to backlog here — `/dr-archive` handles backlog writes to keep the workflow clean.
8.  **OUTPUT**: `datarim/reflection/reflection-[id].md`.

## Next Steps
- Evolution proposals pending? → Apply approved changes
- Health check flagged issues? → `/dr-optimize`
- Task complete? → `/dr-archive` (will handle backlog updates and follow-up task creation)
