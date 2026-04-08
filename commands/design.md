---
name: design
description: Explore architectural and design decisions for complex features (Level 3-4)
---

# /design - Architecture & Design Mode

**Role**: Architect Agent
**Source**: `$HOME/.claude/agents/architect.md`

## Instructions
1.  **LOAD**: Read `$HOME/.claude/agents/architect.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/init`. Do NOT create it — only `/init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **CONTEXT**: Read `datarim/tasks.md` and `datarim/systemPatterns.md`.
3.  **ACTION**:
    - Identify components needing design.
    - Create `datarim/creative/creative-[id]-[name].md`.
    - Document decisions and tradeoffs.
    - **Consilium** (for L3-4 tasks):
        - Load `$HOME/.claude/skills/consilium.md`.
        - Assemble relevant agent panel based on the design question.
        - Run pipeline: SCOPE -> ASSEMBLE -> ANALYZE -> DEBATE -> CONVERGE -> DELIVER.
        - Include conflict resolution via Priority Ladder.
        - Output includes Failure Mode Table.
4.  **OUTPUT**: New creative docs + `tasks.md` update. For L3-4 tasks, output also includes consilium panel summary, key debates, resolutions, and Failure Mode Table.

## Next Steps
- Design complete? → `/do`
