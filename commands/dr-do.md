---
name: dr-do
description: Implement planned changes using TDD and AI quality principles
---

# /dr-do - Implementation Mode

**Role**: Developer Agent
**Source**: `$HOME/.claude/agents/developer.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/developer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **SKILL**: Read `$HOME/.claude/skills/ai-quality.md` (apply rules #2, #3, #8, #9 — see § Stage-Rule Mapping).
5.  **CONTEXT**: Read `datarim/tasks.md` (Implementation Plan for the resolved task).

6.  **PRE-FLIGHT CHECK** (L3-L4 code tasks only):
    Before writing any code, verify readiness:
    ```
    [ ] Plan document exists and is complete (datarim/tasks.md has implementation steps)?
    [ ] Design documents exist if /dr-design was required (datarim/creative/)?
    [ ] Required dependencies are available (check package.json, requirements.txt, etc.)?
    [ ] Project builds/runs in current state (no pre-existing broken state)?
    ```
    If any check fails — fix before implementing. Do not start coding on a broken foundation.

7.  **ACTION**:
    - **TDD Loop**: Write test -> Fail -> Code -> Pass.
    - Implement one stub/method at a time.
    - Follow `datarim/patterns.md` and `datarim/style-guide.md`.
    - Apply quality rules: max 50 lines/method, max 7-9 objects in scope, tests before code.

7.5 **GAP DISCOVERY** (during implementation):
    If you encounter an unknown that blocks progress (import failure, unexpected API behavior, docs ≠ reality, missing feature, compatibility issue):
    -   Load `$HOME/.claude/skills/research-workflow.md` § Gap Discovery Protocol.
    -   Spawn researcher subagent (`$HOME/.claude/agents/researcher.md`) with a focused query describing the specific gap.
    -   Researcher appends findings to `datarim/insights/INSIGHTS-{task-id}.md` § Gap Discoveries.
    -   If gap is fundamental (wrong stack, impossible requirement): STOP. Recommend operator run `/dr-prd` to revise requirements.
    -   Otherwise: continue implementation with updated context.

8.  **REVIEW-FEEDBACK HANDLING** (when an automated code review or human review returns findings):
    Classify each finding, then act:
    - **Critical / blocking** → fix in the current MR before merge. Non-negotiable.
    - **Warning / suggestion that is cheap and strictly better** (1–5 lines, no new abstractions, no scope change)
      → fix inline in the current MR, same round. Examples: tighten a string match (`includes` → `endsWith`),
      remove a blocking `alert()`, rename an obvious typo, add a missing null-guard.
    - **Warning / suggestion that needs design, spans files, or is speculative** → defer to a new backlog item
      with a **concrete trigger** (e.g. "after 14 days post-deploy", "when a second consumer appears",
      "before the next auth refactor"). Do not leave vague follow-ups.
    - **Reject** → only if you have technical grounds, and you must record the rationale in the MR thread.
    Log the disposition (fix / defer / reject) of every finding in the MR thread so reviewers can see their
    feedback was processed, not silently ignored. Commit code changes and backlog additions together in the
    same review round.

9.  **OUTPUT** (thin-index schema):
    -   Code changes (committed per Workspace Discipline rules in CLAUDE.md).
    -   Update `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes with implementation log (or `## Decisions` for design choices). Description file frontmatter `status` stays `in_progress` until `/dr-archive`.
    -   Update `datarim/tasks.md` one-liner if status transitions (e.g. `in_progress` → `blocked`); the line itself stays in canonical thin-index format.
    -   Backlog updates if subtasks discovered (new `pending` one-liners in `datarim/backlog.md`).
    -   **Never write `datarim/progress.md`** (abolished as of v1.19.0). Per-task notes go in the description file; cross-task completion log is `activeContext.md` § «Последние завершённые», populated by `/dr-archive`.

## Transition Checkpoint

Before proceeding to `/dr-qa` or `/dr-archive`:
```
[ ] All planned changes implemented?
[ ] Tests written and passing?
[ ] tasks/{TASK-ID}-task-description.md updated with implementation notes?
[ ] No known regressions introduced?
```

## Next Steps (CTA)

After implementation, the developer agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-do`:**

- All checks pass, L3-4 → primary `/dr-qa {TASK-ID}` (multi-layer verification)
- All checks pass, L1-2 → primary `/dr-archive {TASK-ID}` (reflection runs as Step 0.5)
- Checks incomplete → primary `/dr-do {TASK-ID}` (continue) + alternative `/dr-status`
- Fundamental gap discovered (Gap Discovery escalation) → primary `/dr-prd {TASK-ID}` (revise requirements)

The CTA block MUST follow the canonical format (numbered list, one `**рекомендуется**`, `---` HR wrapping, task ID included). Variant B menu when >1 active tasks.
