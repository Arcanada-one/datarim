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
    -   **Pre-save validation gates (MANDATORY before write):**
        - **`ships_in:` derivation.** If the PRD ships a framework / library release, read the canonical version source (e.g. `code/datarim/VERSION` or project equivalent) and pre-fill `ships_in: <next-minor-or-patch>`. Operator-supplied override requires an inline justification comment in the PRD body. Do not echo the value from memory or from the parent PRD verbatim — version drift between PRD draft and release is a recurring defect class.
        - **V-AC path live-validation.** For every AC / V-AC line citing a script, binary, spec file, or directory path: run `command -v <bin>` / `test -f <path>` / dry-run probe and confirm exit 0 before save. Cites that do not exist yet MUST be marked `[to-be-created]` inline so the gate distinguishes intentional plan-deliverables from typos / phantom paths. Block save if a non-`[to-be-created]` cite fails the probe.
    -   Save to `datarim/prd/PRD-{slug}.md`.

5.5. **Network Exposure Baseline (tiered gate)**:
    -   Read `$HOME/.claude/skills/network-exposure-baseline.md` § Tier Model + § Tiered Gate Rules.
    -   Decide gate disposition by invoking the canonical executor:
        ```bash
        decision=$(dev-tools/network-exposure-gate.sh \
            --task-description datarim/tasks/{TASK-ID}-task-description.md \
            --quiet)
        ```
        Resolve the path to `dev-tools/` via the runtime root (`$HOME/.claude/` symlinks to `code/datarim/`).
    -   Apply the decision:
        -   **`hard_block`** → the PRD MUST include a section titled **«Network Exposure Baseline»** with:
            (a) declared default Tier per port/listener affected by this task
                (`Tier 0` socket, `Tier 1` loopback, `Tier 2` Tailscale, or
                `Tier 3` public);
            (b) for any Tier 3 entry: justification text + `expires` date
                (≤90 days from PRD authorship); and
            (c) explicit acceptance criterion that the verifier
                (`dev-tools/network-exposure-check.sh`) passes against the
                proposed configuration.
            Missing section ⇒ PRD is incomplete, do not advance to `/dr-plan`.
        -   **`advisory_warn`** → include the section if the task touches a
            networking surface; otherwise mention exposure stance in one
            sentence in § Risks. Do not block.
        -   **`skip`** → no PRD section required.
    -   The gate is **fail-closed**: missing or malformed `priority`/`type`
        frontmatter resolves to `hard_block`. Fix the description before
        re-running.

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
