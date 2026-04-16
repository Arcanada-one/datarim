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
3.  **SKILL**: Read `$HOME/.claude/skills/ai-quality.md` (apply rules #2, #3, #8, #9 — see § Stage-Rule Mapping).
4.  **CONTEXT**: Read `datarim/tasks.md` (Implementation Plan).

5.  **PRE-FLIGHT CHECK** (L3-L4 code tasks only):
    Before writing any code, verify readiness:
    ```
    [ ] Plan document exists and is complete (datarim/tasks.md has implementation steps)?
    [ ] Design documents exist if /dr-design was required (datarim/creative/)?
    [ ] Required dependencies are available (check package.json, requirements.txt, etc.)?
    [ ] Project builds/runs in current state (no pre-existing broken state)?
    ```
    If any check fails — fix before implementing. Do not start coding on a broken foundation.

6.  **ACTION**:
    - **TDD Loop**: Write test -> Fail -> Code -> Pass.
    - Implement one stub/method at a time.
    - Follow `datarim/patterns.md` and `datarim/style-guide.md`.
    - Apply quality rules: max 50 lines/method, max 7-9 objects in scope, tests before code.

7.  **REVIEW-FEEDBACK HANDLING** (when an automated code review or human review returns findings):
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

8.  **OUTPUT**: Code changes + `progress.md` update + backlog updates (if any).

## Transition Checkpoint

Before proceeding to `/dr-qa` or `/dr-reflect`:
```
[ ] All planned changes implemented?
[ ] Tests written and passing?
[ ] progress.md updated with implementation details?
[ ] No known regressions introduced?
```

## Next Steps
- All checks pass, L3-4? → `/dr-qa`
- All checks pass, L1-2? → `/dr-reflect`
- Checks incomplete? → Continue implementation
