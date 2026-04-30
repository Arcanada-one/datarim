---
description: Generate a Product Requirements Document (PRD) with rigorous design analysis (Context, Solution Exploration, Consultation).
globs:
  - datarim/projectbrief.md
  - datarim/techContext.md
  - datarim/systemPatterns.md
  - $HOME/.claude/templates/prd-template.md
---

# PRD Generation Command

This command generates a structured Product Requirements Document (PRD) following the **Enhanced Design Process** (Phases 1-3).

## Instructions

0.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

1.  **Analyze Context (Phase 1)**:
    -   Read `datarim/projectbrief.md`, `techContext.md`, and `systemPatterns.md`.
    -   Identify affected components and constraints (Security, Performance).
    -   Read relevant source code files to understand current implementation.

1.5. **Research External Context (Phase 1.3)** (L2+ only):
    -   Determine research mode: **Lite** (L2, 5 checkpoints) or **Full** (L3-L4, 10 checkpoints). Skip entirely for L1.
    -   Load `$HOME/.claude/skills/research-workflow.md`.
    -   Spawn researcher agent (`$HOME/.claude/agents/researcher.md`) with task context: task ID, description, identified stack/dependencies from Phase 1.
    -   Agent creates `datarim/insights/INSIGHTS-{task-id}.md` from template `$HOME/.claude/templates/insights-template.md`.
    -   Agent runs research checklist per mode, using available tools adaptively (context7, WebSearch, LTM API, codebase analysis).
    -   If insights document already exists (e.g., from a previous `/dr-prd` run), update rather than overwrite.

2.  **Discovery Interview (Phase 1.5)**:
    -   If `datarim/insights/INSIGHTS-{task-id}.md` exists, read it before starting the interview — use research findings to inform questions and proposals.
    -   Load `$HOME/.claude/skills/discovery.md`.
    -   Run a focused interview (mode based on complexity: Quick for L1-2, Standard for L2-3, Deep for L3-4).
    -   Apply codebase-first rule: prioritize existing code patterns and constraints over assumptions.
    -   Output structured requirements summary into the PRD discovery section.
    -   For L3-4 tasks, optionally invoke consilium skill (`$HOME/.claude/skills/consilium.md`) for multi-perspective analysis of requirements.

3.  **Explore Solutions (Phase 2)**:
    -   Generate **3+ distinct technical approaches**.
    -   Evaluate each against criteria: Security, Pattern Alignment, DRY, Testability.
    -   Reject approaches with **Anti-Patterns** (e.g., hardcoded secrets, raw SQL).

4.  **Consult User (Phase 3)**:
    -   Present the alternatives clearly.
    -   Wait for user approval on the selected approach.

5.  **Generate PRD**:
    -   Use the structure from `$HOME/.claude/templates/prd-template.md`.
    -   Include: Problem Statement, Scope, Context Analysis, Technical Approach (Selected + Alternatives), Success Criteria, Risks.
    -   If insights document was created in Phase 1.3, add a reference in the PRD header: `**Research:** [INSIGHTS-{task-id}](../insights/INSIGHTS-{task-id}.md)`
    -   Save to `datarim/prd/PRD-{slug}.md`.

6.  **Backlog Generation** (optional):
    -   Extract actionable items from PRD sections (features, components, migrations, integrations).
    -   **Determine prefix for generated items** per Unified Task Numbering (`$HOME/.claude/skills/datarim-system.md`):
        - If PRD is scoped to one project → use that project's prefix.
          <!-- gate:history-allowed -->
          Example: PRD-SUP-0001 → items are `SUP-0002`, `SUP-0003`, ...
          <!-- /gate:history-allowed -->
        - If PRD is cross-project → use area prefix (e.g., `INFRA-NNNN` for infrastructure work)
    -   Scan existing tasks and backlog to determine next sequential number per prefix.
    -   Present to user: "PRD identifies N potential backlog items: [numbered list with proposed IDs, titles, complexity]"
    -   If approved: create entries in `datarim/backlog.md` with status `pending` and a reference to PRD in the description (e.g., `Source: PRD-{ID}`).

7.  **Output Summary**:
    -   Confirm file location.
    -   List next steps: `/dr-init`, `/dr-plan`.

## Template Structure

The PRD MUST include:
-   **Context & Analysis**: Existing code insights, Constraints.
-   **Technical Approach**: Proposed solution, Alternatives considered (Pros/Cons).
-   **Risks & Mitigation**: Security and technical risks.
-   **Success Criteria**: Measurable outcomes.

## Usage

Run: `/dr-prd "Brief description of the task"`

## Next Steps (CTA)

After PRD save, the architect agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-prd`:**

- PRD approved, L3-4 → primary `/dr-plan {TASK-ID}` (detailed implementation plan)
- PRD approved, L2 → primary `/dr-plan {TASK-ID}` (planning phase)
- PRD approved, L1 → primary `/dr-do {TASK-ID}` (skip planning for trivial fix)
- Backlog items proposed and accepted → mention "N items added to backlog" + primary `/dr-plan {TASK-ID}`
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B menu when >1 active tasks.
