---
name: dr-design
description: Explore architectural and design decisions for complex features (Level 3-4)
---

# /dr-design - Architecture & Design Mode

**Role**: Architect Agent
**Source**: `$HOME/.claude/agents/architect.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/architect.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **CONTEXT**: Read `datarim/tasks.md` and `datarim/systemPatterns.md`.

4.  **DETERMINE DESIGN TYPE**: Classify each component needing design into one of these types:

    | Type | When | Key Activities |
    |------|------|----------------|
    | **UI/UX Design** | User-facing interfaces, layouts, flows | User flow analysis, component hierarchy, interaction patterns, visual principles |
    | **Architecture Design** | System structure, component organization | Component structure, data flow, interface design, system integration, diagrams |
    | **Data Model Design** | Database schemas, entity relationships | Entity relationships, schema design, validation rules, query optimization |
    | **Algorithm Design** | Complex logic, processing pipelines | Complexity analysis, efficiency optimization, edge case handling, scaling |

5.  **FOR EACH COMPONENT** — execute the creative phase:
    - **Define problem** clearly and specifically.
    - **Explore 3+ options** with different approaches.
    - **Analyze tradeoffs** — pros, cons, complexity, effort for each option.
    - **Make decision** with clear rationale.
    - **Document implementation plan** — specific steps to realize the decision.
    - **Visualize** — include diagrams (mermaid) where helpful.
    - **Apply quality rules**: #6 Corner Cases, #7 Skeleton, #9 Cognitive Load, #13 Transactions (see `ai-quality.md` § Stage-Rule Mapping).

6.  **CREATE DOCUMENT**: `datarim/creative/creative-[task_id]-[type]-[name].md`
    - Format: Problem → Options (3+) → Pros/Cons → Decision → Implementation Plan → Visualization

7.  **CONSILIUM** (for L3-4 tasks):
    - Load `$HOME/.claude/skills/consilium.md`.
    - Assemble relevant agent panel based on the design question.
    - Run pipeline: SCOPE -> ASSEMBLE -> ANALYZE -> DEBATE -> CONVERGE -> DELIVER.
    - Include conflict resolution via Priority Ladder.
    - Output includes Failure Mode Table.
    - **Waiver:** If one option clearly dominates all others across every tradeoff dimension, Consilium may be waived. Record: "Consilium waived — Option X dominates (see tradeoff table)" in the creative document. Include a Failure Mode Table regardless (lightweight version acceptable).

8.  **OUTPUT**: New creative docs + `tasks.md` update. For L3-4 tasks, output also includes consilium panel summary, key debates, resolutions, and Failure Mode Table.

## Transition Checkpoint

Before proceeding to `/dr-do`:
```
[ ] Problem clearly defined for each component?
[ ] 3+ options analyzed with tradeoffs?
[ ] Decision made with documented rationale?
[ ] Implementation plan included?
[ ] tasks.md updated with design decisions?
```

## Next Steps
- All checks pass? → `/dr-do`
- Missing items? → Complete before transition
