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

1.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.

2.  **Analyze Context**:
    -   Read `datarim/tasks.md` (Complexity, Requirements for the resolved task).
    -   Read `datarim/activeContext.md` (Active Tasks list).
    -   Review `datarim/prd/*.md` if available.

3.  **Strategist Gate** (mandatory for L3-4, optional for L2):
    -   Load `$HOME/.claude/agents/strategist.md`.
    -   Evaluate:
        -   **Value** — is this worth building?
        -   **Risk** — what's irreversible?
        -   **Cost** — what's the minimum viable experiment?
    -   If strategist recommends pivot or cheaper alternative, present to user before proceeding.

4.  **Detailed Design (Phase 4)**:
    -   **Component Breakdown**: List every modified and new file.
    -   **Interface Design**: Define function signatures, API contracts.
    -   **Data Flow**: Trace input -> processing -> output.
    -   **Security Design**: Perform **Threat Modeling** and map to **Security Controls** (Appendix A).

5.  **Create Implementation Plan (Phase 5)**:
    -   **L1-L2 tasks:** Write plan inline in `datarim/tasks.md` task entry.
    -   **L3-L4 tasks:** Write plan to `datarim/plans/{TASK-ID}-plan.md`. In the task entry in `tasks.md`, add only a pointer: `**Implementation Plan:** [datarim/plans/{TASK-ID}-plan.md](plans/{TASK-ID}-plan.md)`.
    -   Both formats use the same **Design Document Template**.
    -   Include: **Security Summary** (Attack Surface, Risks), **Architecture Impact**, **Detailed Design** (API, DB, Config), **Security Design** (Threats, Controls), **Implementation Steps**, **Test Plan** (Unit/Integration/Security), **Rollback Strategy**, **Validation Checklist**.

6.  **Technology Validation**:
    -   Document technology stack selection.
    -   Verify dependencies and build configuration.

7.  **Installer / Deploy-Script Content-Type Audit (MANDATORY when plan touches install.sh, sync-script, or any deploy/copy tool)**:
    -   Grep the file-type filter (`case "*.md"`, `find ... -name`, extension whitelist, etc.) in the target script.
    -   List every supported extension explicitly in the plan's Technology Validation or Architecture Impact section.
    -   If the plan promotes/adds files with an extension the installer does NOT handle, either:
        - (a) Extend the installer filter in the same plan (add to scope), or
        - (b) Record the gap as an explicit known-limitation and open a follow-up backlog item to fix the installer.
    -   Rationale: TUNE-0003 Phase 5 discovered that `install.sh:56 case "*.md"` silently excluded `.sh` templates — the gap was readable from line 1 but surfaced only at verification. Grepping the filter at planning time catches this class of asymmetry.

8.  **Research Kill-Criteria Checkpoint** (for comparative/research tasks):
    -   After research but BEFORE mechanical testing (smoke-install, Docker runs, benchmarks): evaluate whether research evidence alone eliminates candidates (deprecated, stale, wrong license, wrong category, hype).
    -   Candidates failing kill-criteria from research skip testing entirely — saves hours of Docker/install time.
    -   Rationale: LTM-0001 eliminated 7 of 13 candidates from research evidence alone, saving ~4.5h of Docker smoke-runs.

9.  **Planning Hygiene — Summary Counts from Source Table**:
    -   Any aggregate count in the plan (e.g. "total deferred", "files touched", "rows", "threats") MUST be derived from the authoritative source table (drift report, component breakdown, threat model) and the plan MUST cite that source inline.
    -   Freehand summary numbers are prohibited — they propagate into validation checklists and blur AC verification.
    -   Example: not `"12 deferred diffs"` but `"14 deferred diffs (from drift-TUNE-0003.md: 8 skills + 2 agents + 4 commands)"`.

10.  **Fixture Capture for External Output (MANDATORY when the plan parses a CLI / subprocess / API response)**:
    -   When the task depends on an external tool's output format (CLI, subprocess, webhook, HTTP API, log stream), capture a **real** sample during `/dr-plan` and commit it to `datarim/tasks/{TASK-ID}-fixtures.md` with timestamp, tool version, command invoked, and all relevant output formats.
    -   Do NOT design a parser against the documented or inferred format alone when a live sample is reachable. Documentation drifts, versions vary, and the fastest path to a correct parser is a fixture you can paste into a test.
    -   Prefer the tool's machine-readable output (`--json`, `--output-format stream-json`, `--format porcelain`) over human-text; structural fields are stable, prose drifts. If the plan proposes regex-on-human-text while a machine format is available, stop and revisit.
    -   If a live failure window is already open (e.g. a production service in an error state), capture the fixture AND run the end-to-end smoke test in the same session — limit windows close fast and cannot be recreated on demand.
    -   Rationale: DEV-1183 plan initially proposed regex parsing of `"resets 5pm (UTC)"`. A 30-min live capture during `/dr-plan` surfaced a machine-readable `rate_limit_event.rate_limit_info.resetsAt` UNIX epoch — strictly better (no TZ/locale fragility, future-proof for new limit types). Without the capture, the plan would have shipped a locale-fragile parser.
    -   **Known CLI agent pattern — exit code 0 on JSON errors:** Many CLI agents (Claude Code, Cursor, likely Gemini/Codex) return exit code 0 even when the JSON output contains `is_error: true`. The error is encoded inside JSON, not signaled by the process exit code. When capturing fixtures, always capture both a success AND an error case to verify exit code behavior. Parsers must check `is_error`/`subtype` in JSON, not rely on exit codes. (CONN-0003: Claude CLI returns exit 0 for `error_max_turns` with errors inside JSON.)

11.  **Output Summary**:
    -   Confirm task status update.
    -   List next steps by complexity:
        -   L3-4 → `/dr-design`
        -   L1-2 → `/dr-do`

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
[ ] Live fixture captured into `datarim/tasks/{TASK-ID}-fixtures.md` if the plan parses any external tool output (CLI/API/subprocess/log)? (DEV-1183: empirical capture replaced locale-fragile regex with structural epoch parsing.)
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
