---
description: Create detailed implementation plan (Phases 4-6, Appendix A Security).
globs:
  - datarim/tasks.md
  - datarim/activeContext.md
  - datarim/prd/*.md
---

# PLAN Command

This command generates a detailed implementation plan in `datarim/tasks.md`, strictly following the **Enhanced Design Process** (Phases 4-6).

## Instructions

0.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

1.  **Analyze Context**:
    -   Read `datarim/tasks.md` (Complexity, Requirements).
    -   Read `datarim/activeContext.md` (Current Context).
    -   Review `datarim/prd/*.md` if available.

2.  **Strategist Gate** (mandatory for L3-4, optional for L2):
    -   Load `$HOME/.claude/agents/strategist.md`.
    -   Evaluate:
        -   **Value** — is this worth building?
        -   **Risk** — what's irreversible?
        -   **Cost** — what's the minimum viable experiment?
    -   If strategist recommends pivot or cheaper alternative, present to user before proceeding.

3.  **Detailed Design (Phase 4)**:
    -   **Component Breakdown**: List every modified and new file.
    -   **Interface Design**: Define function signatures, API contracts.
    -   **Data Flow**: Trace input -> processing -> output.
    -   **Security Design**: Perform **Threat Modeling** and map to **Security Controls** (Appendix A).

4.  **Create Implementation Plan (Phase 5)**:
    -   Update `datarim/tasks.md` using the **Design Document Template**.
    -   Include: **Security Summary** (Attack Surface, Risks), **Architecture Impact**, **Detailed Design** (API, DB, Config), **Security Design** (Threats, Controls), **Implementation Steps**, **Test Plan** (Unit/Integration/Security), **Rollback Strategy**, **Validation Checklist**.

5.  **Technology Validation**:
    -   Document technology stack selection.
    -   Verify dependencies and build configuration.

6.  **Installer / Deploy-Script Content-Type Audit (MANDATORY when plan touches install.sh, sync-script, or any deploy/copy tool)**:
    -   Grep the file-type filter (`case "*.md"`, `find ... -name`, extension whitelist, etc.) in the target script.
    -   List every supported extension explicitly in the plan's Technology Validation or Architecture Impact section.
    -   If the plan promotes/adds files with an extension the installer does NOT handle, either:
        - (a) Extend the installer filter in the same plan (add to scope), or
        - (b) Record the gap as an explicit known-limitation and open a follow-up backlog item to fix the installer.
    -   Rationale: TUNE-0003 Phase 5 discovered that `install.sh:56 case "*.md"` silently excluded `.sh` templates — the gap was readable from line 1 but surfaced only at verification. Grepping the filter at planning time catches this class of asymmetry.

7.  **Research Kill-Criteria Checkpoint** (for comparative/research tasks):
    -   After research but BEFORE mechanical testing (smoke-install, Docker runs, benchmarks): evaluate whether research evidence alone eliminates candidates (deprecated, stale, wrong license, wrong category, hype).
    -   Candidates failing kill-criteria from research skip testing entirely — saves hours of Docker/install time.
    -   Rationale: LTM-0001 eliminated 7 of 13 candidates from research evidence alone, saving ~4.5h of Docker smoke-runs.

8.  **Planning Hygiene — Summary Counts from Source Table**:
    -   Any aggregate count in the plan (e.g. "total deferred", "files touched", "rows", "threats") MUST be derived from the authoritative source table (drift report, component breakdown, threat model) and the plan MUST cite that source inline.
    -   Freehand summary numbers are prohibited — they propagate into validation checklists and blur AC verification.
    -   Example: not `"12 deferred diffs"` but `"14 deferred diffs (from drift-TUNE-0003.md: 8 skills + 2 agents + 4 commands)"`.

8.  **Output Summary**:
    -   Confirm task status update.
    -   List next steps: `/dr-do`.

## Template Structure (Design Document)

The plan in `datarim/tasks.md` MUST include: **Overview**, **Security Summary** (Attack Surface, Risks), **Architecture Impact**, **Detailed Design** (components, API, DB), **Security Design** (Threat Model, Appendix A controls), **Implementation Steps**, **Test Plan**, **Rollback Strategy**, **Validation Checklist**, **Next Steps**. (Enhanced Design Process Phases 4-6.)

## Security Requirements (Appendix A)

-   **Principles**: Fail-closed, Least privilege, No secrets in code/logs.
-   **Anti-Patterns**: Trusting user input, Logging sensitive data, Hardcoding secrets, SQL concatenation, Unvalidated file paths.

## Transition Checkpoint

Before proceeding to `/dr-design` or `/dr-do`:
```
[ ] Requirements clearly documented?
[ ] Components and affected files identified?
[ ] Installer/deploy-script content-type audit done (if plan touches install.sh / sync / deploy)?
[ ] All aggregate counts in plan derived from source tables (not freehand)?
[ ] Definition of Done is testable and explicit?
[ ] Boundaries stated (what we DON'T do)?
[ ] Technology stack validated (if applicable)?
[ ] Rollback strategy viable? (verify commands actually work — e.g., is the target a git repo?)
[ ] For TDD sections of the plan: each test assertion traced through *current* (pre-fix) code state before being labelled expected-pass or expected-fail? (TUNE-0004 QA NOTE-2: a plan predicting "3 of 4 drift tests pass before fix" was wrong because the predictions were not checked against the actual `diff -rq` behaviour with the bug still present.)
[ ] tasks.md updated with implementation plan?
```

## Usage

Run: `/dr-plan`
