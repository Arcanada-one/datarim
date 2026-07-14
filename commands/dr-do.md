---
name: dr-do
description: Implement planned changes using TDD and AI quality principles
---

# /dr-do - Implementation Mode

**Role**: Developer Agent
**Source**: `$HOME/.claude/agents/developer.md`

## Instructions


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
1.  **LOAD**: Read `$HOME/.claude/agents/developer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.
3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **SKILL**: Read `$HOME/.claude/skills/ai-quality/SKILL.md` (apply rules #2, #3, #8, #9 — see § Stage-Rule Mapping).
5.  **CONTEXT**: Read `datarim/tasks.md` (Implementation Plan for the resolved task). Additionally, read `datarim/tasks/{TASK-ID}-init-task.md` if present (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): the verbatim operator brief + every append-log block. Any divergence between the operator's stated intent and the planned implementation MUST be recorded in `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes. Missing init-task is non-blocking — flag as advisory and continue.

5.5. **OPERATOR-MANDATED DELEGATION FLOW** (MANDATORY when the operator's project / global CLAUDE.md declares a hook-enforced delegation rule for the artefact type being produced — e.g. «always delegate first, then edit» for archive docs, blog posts, PRD drafts, reflection files):
    -   Use the delegated flow for the first draft. If the harness has a hook that hard-blocks direct write of the target path, the block is the contract working as intended — do not retry with a different write mechanism or argue with the hook output.
    -   After the delegated generator completes, apply surgical edits to the produced file (judgment-parts only — verbatim copy of generated content is forbidden per the mandate's «never accept blindly» clause).
    -   Record the delegation invocation in `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes — one line per delegated artefact, citing the provider + profile + target path. `/dr-qa` Layer 3b cross-checks this line against the touched files.
    -   Bypass is permitted ONLY when (a) the harness hook explicitly returned an allow decision (operator override at runtime) AND (b) the override reason is recorded in the same § Implementation Notes line. Silent bypass = process regression; `/dr-compliance` will surface it.
    -   Rationale: hook-enforced mandates exist because the operator decided the delegation matters — for token economics, for content review discipline, or for security. Working around the hook to save time negates the operator's design decision and creates inconsistent artefact provenance across the task lifecycle.

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
    - Follow `datarim/history/patterns.md` and `datarim/style-guide.md`.
    - Apply quality rules: max 50 lines/method, max 7-9 objects in scope, tests before code.

7.5 **GAP DISCOVERY** (during implementation):
    If you encounter an unknown that blocks progress (import failure, unexpected API behavior, docs ≠ reality, missing feature, compatibility issue):
    -   Load `$HOME/.claude/skills/research-workflow/SKILL.md` § Gap Discovery Protocol.
    -   Spawn researcher subagent (`$HOME/.claude/agents/researcher.md`) with a focused query describing the specific gap.
    -   Researcher appends findings to `datarim/insights/INSIGHTS-{task-id}.md` § Gap Discoveries.
    -   If gap is fundamental (wrong stack, impossible requirement): STOP. Recommend operator run `/dr-prd` to revise requirements.
    -   Otherwise: continue implementation with updated context.

7.6. **AUTOMATIC SPEC-GRAPH EVIDENCE CHECK**:
    -   As tests and verification artifacts are produced, append canonical lines to the task implementation record:
        `Evidence: V-AC-N — <exact command, test, measurement, or artifact path>`.
    -   Before routing onward, invoke:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/spec-graph-gate.sh" \
            --task {TASK-ID} --stage do --root <repo-root> --format json
        ```
    -   The do-stage gate is advisory even when hard mode is active because evidence is still accruing. Exit `2` remains fail-closed.

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

8.5. **NETWORK EXPOSURE PRE-COMMIT GATE** (MANDATORY when staged changes touch a networking surface):
    -   Before invoking `git commit`, scan the staged diff for changes to:
        docker-compose `ports`/`expose`, `redis.conf`, `postgresql.conf`,
        systemd `.socket`, firewall/UFW rules, or runtime bind arguments. If
        none, skip this step.
    -   Run the verifier on every modified networking-config file in the
        staged set:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-check.sh" \
            --compose <staged-compose>... \
            --redis-conf <staged-redis>... \
            --postgres-conf <staged-postgres>... \
            --systemd-socket <staged-socket>...
        ```
        Exit code `1` from the verifier ⇒ **STOP**, do not commit. Fix the
        violation per `$HOME/.claude/skills/network-exposure-baseline/SKILL.md`
        (loopback / Tailscale / Tier 3 with valid `x-exposure-justification`
        + `x-exposure-expires` ≤ 90 d).
    -   Run the tiered gate to confirm enforcement strictness:
        ```bash
        decision=$("${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-gate.sh" \
            --task-description datarim/tasks/{TASK-ID}-task-description.md \
            --network-diff --quiet)
        ```
        On `hard_block` the verifier failure is non-overridable; on
        `advisory_warn` the operator MAY override with `--skip-exposure-gate`,
        which MUST emit an Ops Bot event:
        `POST https://ops.arcanada.one/events` with
        `{category: warning, agent: dr-do, task: {TASK-ID}, body: "network-exposure-gate skipped"}`
        and a one-line note in
        `datarim/tasks/{TASK-ID}-task-description.md` § Decisions explaining
        the override rationale and remediation date.
    -   The gate is fail-closed: missing/malformed `priority`/`type`
        frontmatter resolves to `hard_block` regardless of the
        `--skip-exposure-gate` flag.

8.6. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract): for every operator clarification round captured during implementation — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh"` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log`.
    -   Write the question, answer, and rationale (when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1.
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage do --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` MUST contain ≥ 50 non-whitespace characters of justification.
    -   On contradiction with an expectation discovered mid-implementation: add `--conflict-with <wish_id>`; CTA MUST route back to `/dr-do --focus-items <wish_id>` after the conflict closure entry lands.
    -   Skip if no clarification rounds occurred.
    -   **Applies to every round** (round 1, round 2, …) of `/dr-do` invocation — including post-`/dr-verify` triage and `--focus=` re-entry. Round number MUST monotonically increase; do not reuse `--round N` from a prior call. Missing append triggers `/dr-qa` Layer 3b retroactive backfill (a process-cost regression).

9.  **OUTPUT** (thin-index schema):
    -   Code changes (committed per Workspace Discipline rules in CLAUDE.md).
    -   Update `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes with implementation log (or `## Decisions` for design choices). Description file frontmatter `status` stays `in_progress` until `/dr-archive`.
    -   Update `datarim/tasks.md` one-liner if status transitions (e.g. `in_progress` → `blocked`); the line itself stays in canonical thin-index format.
    -   Backlog updates if subtasks discovered (new `pending` one-liners in `datarim/backlog.md`).
    -   **Never write `datarim/progress.md`** (abolished as of v1.19.0). Per-task notes go in the description file; cross-task completion log is `activeContext.md` § «Последние завершённые», populated by `/dr-archive`. <!-- allow-non-ascii: russian-active-context-section-name-cited-from-canonical-schema -->

## Transition Checkpoint

Before proceeding to `/dr-qa` or `/dr-archive`:
```
[ ] All planned changes implemented?
[ ] Tests written and passing?
[ ] tasks/{TASK-ID}-task-description.md updated with implementation notes?
[ ] No known regressions introduced?
[ ] If staged changes touch any networking surface, `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-check.sh"` exited 0 against the staged set and the tiered-gate verdict was honoured (or an `advisory_warn` override was logged with Ops Bot event + § Decisions note)?
```

## /dr-auto Mode (when `DATARIM_AUTO_MODE=1`)

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND the matching per-task marker — resolved via `dev-tools/auto-mode-marker.sh resolve --root <workspace> --task-id <TASK-ID>`, per-task `datarim/.auto/<TASK-ID>.mode` with legacy `datarim/.auto-mode-active` fallback — containing this TASK-ID), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder ([definition](../skills/autonomous-mode/SKILL.md)) before any `AskUserQuestion` or equivalent operator prompt at this stage.
2. Stage-specific suppression hooks:
   - TDD red→green transitions — design choices among equivalent implementations resolved through Ladder L1 (existing pattern grep) before L5.
   - L1 inline gap classifier — discovered gap routed per skills/autonomous-mode/SKILL.md § L1 Inline Resolution Rule decision tree (L1 Class A → inline; L2+/B → backlog; HARD → L5).
   - Append every inline-resolved gap to `datarim/tasks/{TASK-ID}-auto-inline-log.md`.
3. Discovered gaps → apply L1 Inline Resolution Rule per `skills/autonomous-mode/SKILL.md`; log in `datarim/tasks/{TASK-ID}-auto-inline-log.md` if applied inline.
4. Hard-gated actions → escalate to operator through Ladder L5; log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
5. Mismatch (env var set, marker absent OR marker contains different TASK-ID) → emit single-line warning, treat as non-auto (fail-safe per `skills/autonomous-mode/SKILL.md` § When this skill is active).

## Next Steps (CTA)

After implementation, the developer agent MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-do`:**

- All checks pass, L3-4 → primary `/dr-qa {TASK-ID}` (multi-layer verification)
- All checks pass, L1-2 → primary `/dr-archive {TASK-ID}` (reflection runs as Step 0.5)
- Checks incomplete → primary `/dr-do {TASK-ID}` (continue) + alternative `/dr-status`
- Fundamental gap discovered (Gap Discovery escalation) → primary `/dr-prd {TASK-ID}` (revise requirements)

The CTA block MUST follow the canonical format (numbered list, one `**рекомендуется**`, `---` HR wrapping, task ID included). Variant B menu when >1 active tasks. <!-- allow-non-ascii: russian-canonical-cta-marker-tokens-cited-from-cta-format-skill -->

## Stage Snapshot Emission (Mandatory Terminal Step)

After the `## Next Steps (CTA)` block above, the agent MUST perform snapshot emission ([definition](../skills/stage-snapshot-writer/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `do`
- `command`: `/dr-do`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
