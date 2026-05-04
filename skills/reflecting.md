---
name: reflecting
description: Review-phase workflow — lessons learned, evolution proposals (Class A/B gate), health-metrics check. Invoked by /dr-archive Step 0.5.
---

# Reflecting Skill — Review & Self-Evolution Workflow

**Role**: Reviewer Agent
**Source persona**: `$HOME/.claude/agents/reviewer.md`

## Invocation Contract

This skill is **invoked internally by `/dr-archive` Step 0.5** for every completed task. It is **not a standalone command** — the former `/dr-reflect` command was retired in v1.10.0 (TUNE-0013) because reflection must run on every archive, not optionally.

**Trigger:** `/dr-archive` Step 0.5 loads this skill.
**Input:** resolved task state (from Task Resolution Rule in `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule) via `datarim/tasks.md` + `datarim/activeContext.md`. The task ID is already resolved by `/dr-archive` Step 0.
**Output:** `datarim/reflection/reflection-{task-id}.md` + (optional) applied Class A evolution changes + follow-up-task list returned to `/dr-archive` Step 4.
**Failure mode:** if skill load fails or user rejects Class A proposals → STOP archive; do NOT proceed to Step 1 of `/dr-archive`. Archive is idempotent — re-running re-enters Step 0.5.

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/reviewer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **SKILL**: Read `$HOME/.claude/skills/security.md` and `$HOME/.claude/skills/testing.md`.
4.  **CONTEXT**: Read `datarim/tasks.md` and `datarim/style-guide.md`.
5.  **ACTION**:
    - Review changes against Definition of Done.
    - Verify tests pass.
    - Check for security vulnerabilities.
    - Create reflection document using `$HOME/.claude/templates/reflection-template.md` (fallback to `datarim/templates/reflection-template.md` only if project provides a custom template).
6.  **EVOLUTION**:
    - Load `$HOME/.claude/skills/evolution.md` **by reference** (Read it at runtime — do not duplicate its Class A/B gate here; single source of truth per TUNE-0012).
    - Analyze: what worked well? what was inefficient? any missing skills/patterns?
    - Generate evolution proposals (categories: `skill-update`, `agent-update`, `claude-md-update`, `new-template`, `new-skill`).
    - **Classify each proposal as Class A or Class B** per `evolution.md` § "Class A vs Class B — Operating-Model Gate". Class A = content changes (approval-ready). Class B = operating-model / contract changes (source-of-truth direction, sync semantics, pipeline routing, core contract, command semantics). Class B proposals **must not be presented for user approval** until a PRD update (or project-level contract equivalent) is drafted; pause and request the PRD draft instead.
    - Present Class A proposals to user for approval. Hold Class B until PRD is updated, then re-present.
    - **Stack-agnostic gate (MANDATORY before write):** before applying any approved Class A proposal that writes to `$HOME/.claude/{skills,agents,commands,templates}/`, load `$HOME/.claude/skills/evolution/stack-agnostic-gate.md` and run the gate against the proposal text (script form: `scripts/stack-agnostic-gate.sh <target>`). FAIL → reject the proposal, do NOT write; reword to stack-neutral or escalate to user as «belongs in project's CLAUDE.md, not framework runtime».
    - **Bats verification (MANDATORY after write):** after applying any approved Class A proposal that touches `skills/`, `agents/`, `commands/`, `templates/`, or `tests/` in the framework repo, run `bats tests/` from the repo root. Failed tests = re-open the proposal as REJECTED with the diff and failing-test names; do NOT log as APPLIED in `evolution-log.md`. Source: TUNE-0040 — TUNE-0039 archive Class A apply (`keyword-linter.md` added) silently broke `tests/utilities-decomposition.bats:T3` (hardcoded count 12 → actual 13); regression detected 1 day late only at TUNE-0040 /dr-do.
    - Log approved changes in `datarim/docs/evolution-log.md`.
7.  **HEALTH CHECK**:
    - Count total skills, agents, commands in the active scope.
    - Check against Health Metrics thresholds (see `evolution.md`).
    - If any threshold is exceeded, suggest: "Framework may benefit from optimization. Run `/dr-optimize` to audit and clean up."
    - This is a suggestion only — do not run optimization automatically.
8.  **FOLLOW-UP TASKS**:
    - Review the "Next Steps" section of the reflection document.
    - **Out-of-scope drift auto-detection (TUNE-0082):** scan implementation notes and "What Didn't" section for phrases indicating drift spotted but not fixed (heuristics: `out-of-scope`, `still stale`, `also stale`, `runtime ... lagging`, `symmetric ... drift`, `separate task`, `deferred`, `noted for follow-up`). For each match, auto-suggest a follow-up backlog entry with proposed prefix + brief title rather than relying on operator memory. Surface the suggestions explicitly in the reflection's "Follow-Up Tasks" section so `/dr-archive` Step 4 picks them up.
    - If follow-up tasks are identified, **return the list to `/dr-archive` Step 4 consumer** (do NOT write to backlog here).
    - `/dr-archive` Step 4 handles backlog writes to keep the workflow clean.
9.  **OUTPUT**: `datarim/reflection/reflection-[id].md`.

## Return to `/dr-archive`

On successful completion, control returns to `/dr-archive` Step 1 (archive-area determination). The reflection document path and the follow-up-task list become inputs to Steps 2 and 4 respectively.

## Historical note

Prior to Datarim v1.10.0 (TUNE-0013), this logic was a standalone command `/dr-reflect` — an optional pipeline stage between `/dr-compliance` and `/dr-archive`. It was consolidated into `/dr-archive` as mandatory Step 0.5 because the "optional mandatory gate" was the anti-pattern: reflection was expected every task yet trivially skippable. The command was removed; the workflow lives here as a skill.
