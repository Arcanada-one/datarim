---
name: reflecting
description: Review-phase workflow — lessons learned, evolution proposals (Class A/B gate), health-metrics check. Invoked by /dr-archive Step 0.5.
current_aal: 1
target_aal: 3
---

# Reflecting Skill — Review & Self-Evolution Workflow

**Role**: Reviewer Agent
**Source persona**: `$HOME/.claude/agents/reviewer.md`

## Invocation Contract

This skill is invoked from **two call-sites**, and is the **single source of truth** for the reflection workflow (never duplicate its steps into either caller):

1. **`/dr-compliance` (primary, on a passing verdict)** — when the compliance verdict is COMPLIANT or COMPLIANT_WITH_NOTES, compliance loads this skill and writes the reflection, stamping `reflection_basis` with the truncated sha256 of the compliance report (`${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/reflection-freshness.sh --emit-basis <report>`). This makes `/dr-compliance` the place reflection normally happens, so it is not lost when a task is hardened but not yet archived.
2. **`/dr-archive` Step 0.5 (conditional fallback)** — archive runs the freshness check (`${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/reflection-freshness.sh --task <ID> --root <root>`) and re-invokes this skill ONLY when the helper exits 1 (reflection absent, `reflection_basis` absent, compliance report absent, or basis stale vs the current compliance report). On exit 0 (basis matches) archive reuses the existing reflection and does NOT re-run this workflow.

The former standalone `/dr-reflect` command was retired in v1.10.0 — do not resurrect it. The mandatory-reflection guarantee is preserved by the four-branch freshness decision: a task that reached archive with no prior `/dr-compliance` still has no reflection file, so the helper exits 1 and archive force-generates.

**Input:** resolved task state (from Task Resolution Rule in `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule) via `datarim/tasks.md` + `datarim/activeContext.md`. The task ID is already resolved by the caller.
**Output:** `datarim/reflection/reflection-{task-id}.md` (with `reflection_basis` frontmatter) + (optional) applied Class A evolution changes + follow-up-task list returned to the caller.
**Failure mode:** if skill load fails or user rejects Class A proposals → STOP the caller; when invoked from `/dr-archive`, do NOT proceed to Step 1. Reflection is idempotent — re-running re-enters this workflow.

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/reviewer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.
3.  **SKILL**: Read `$HOME/.claude/skills/security/SKILL.md` and `$HOME/.claude/skills/testing/SKILL.md`.
4.  **CONTEXT**: Read `datarim/tasks.md` and `datarim/style-guide.md`.
5.  **ACTION**:
    - Review changes against Definition of Done.
    - Verify tests pass.
    - Check for security vulnerabilities.
    - Create reflection document using `${DATARIM_RUNTIME:-$HOME/.claude}/templates/reflection-template.md` (fallback to `datarim/templates/reflection-template.md` only if project provides a custom template).
    - **Stamp `reflection_basis`** in the frontmatter: when a compliance report exists at `datarim/reports/compliance-report-{task-id}.md`, set it to `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/reflection-freshness.sh --emit-basis <report>` output (16-hex). When no compliance report exists (archive-fallback path with a skipped `/dr-compliance`), leave `reflection_basis` empty — archive will then always treat the file as needing regeneration on any later compliance pass, which is the correct conservative behaviour.
6.  **EVOLUTION**:
    - Load `$HOME/.claude/skills/evolution/SKILL.md` **by reference** (Read it at runtime — do not duplicate its Class A/B gate here; single source of truth).
    - Analyze: what worked well? what was inefficient? any missing skills/patterns?
    - Generate evolution proposals (categories: `skill-update`, `agent-update`, `claude-md-update`, `new-template`, `new-skill`, `promote-recurring-incident-to-gate`).
    - **Recurrence check BEFORE any decline (anti-self-suppression — MANDATORY).** Before declining to propose a framework change for a lesson — and especially before writing any "no framework-level evolution proposals this round" / "redundant with existing contract" rationale — run the recurrence check per `skills/evolution/class-ab-gate.md` § Anti-self-suppression rule: tag the lesson with an `incident_class` key and grep prior reflections for it (`grep -REl "incident_class: <key>" datarim/reflection/`); if no key match, semantically compare against the last several reflections. If **either** signals recurrence, the decline reason "redundant with existing contract" is **forbidden** — the lesson MUST be promoted via the `promote-recurring-incident-to-gate` category, and the reflection MUST cite the prior reflection that constitutes the recurrence evidence. A genuinely novel lesson (no prior occurrence) may still be declined. Stamp every lesson with its `incident_class` so future reflections can detect recurrence.
    - **Classify each proposal as Class A or Class B** per `evolution.md` § "Class A vs Class B — Operating-Model Gate". Class A = content changes (approval-ready). Class B = operating-model / contract changes (source-of-truth direction, sync semantics, pipeline routing, core contract, command semantics). Class B proposals **must not be presented for user approval** until a PRD update (or project-level contract equivalent) is drafted; pause and request the PRD draft instead.
    - Present Class A proposals to user for approval. Hold Class B until PRD is updated, then re-present.
    - **Stack-agnostic gate (MANDATORY before write):** before applying any approved Class A proposal that writes to `$HOME/.claude/{skills,agents,commands,templates}/`, load `$HOME/.claude/skills/evolution/stack-agnostic-gate.md` and run the gate against the proposal text (script form: `scripts/stack-agnostic-gate.sh <target>`). FAIL → reject the proposal, do NOT write; reword to stack-neutral or escalate to user as «belongs in project's CLAUDE.md, not framework runtime».
    - **Bats verification (MANDATORY after write):** after applying any approved Class A proposal that touches `skills/`, `agents/`, `commands/`, `templates/`, or `tests/` in the framework repo, run `bats tests/` from the repo root. Failed tests = re-open the proposal as REJECTED with the diff and failing-test names; do NOT log as APPLIED in `evolution-log.md`. Source: prior incident — a Class A apply (`keyword-linter.md` added) silently broke `tests/utilities-decomposition.bats:T3` (hardcoded count 12 → actual 13); regression detected 1 day late only at the subsequent /dr-do.
    - Log approved changes in `datarim/history/evolution-log.md`.
7.  **HEALTH CHECK**:
    - Count total skills, agents, commands in the active scope.
    - Check against Health Metrics thresholds (see `evolution.md`).
    - If any threshold is exceeded, suggest: "Framework may benefit from optimization. Run `/dr-optimize` to audit and clean up."
    - This is a suggestion only — do not run optimization automatically.
8.  **FOLLOW-UP TASKS**:
    - Review the "Next Steps" section of the reflection document.
    - **Out-of-scope drift auto-detection:** scan implementation notes and "What Didn't" section for phrases indicating drift spotted but not fixed (heuristics: `out-of-scope`, `still stale`, `also stale`, `runtime ... lagging`, `symmetric ... drift`, `separate task`, `deferred`, `noted for follow-up`). For each match, auto-suggest a follow-up backlog entry with proposed prefix + brief title rather than relying on operator memory. Surface the suggestions explicitly in the reflection's "Follow-Up Tasks" section so `/dr-archive` Step 4 picks them up.
    - If follow-up tasks are identified, **return the list to `/dr-archive` Step 4 consumer** (do NOT write to backlog here).
    - **Propose the prefix + title ONLY — never a hand-picked ID number.** The concrete task ID is allocated at backlog-write time (`/dr-archive` Step 4) by **running the canonical helper** `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/next-free-id.sh" {PREFIX} "$DATARIM_ROOT"` (or the equivalent `/dr-init` mkdir-mutex reservation), never a hand-computed `max+1`. The helper applies `max(claimed across documentation/archive ∪ datarim/tasks.md ∪ datarim/backlog.md) + 1` and auto-bumps on a parallel-session race, so a task spawning a follow-up cannot collide with a concurrently-created ID (the follow-up-ID rename incident that motivated this rule).
    - `/dr-archive` Step 4 handles backlog writes to keep the workflow clean.
9.  **OUTPUT**: `datarim/reflection/reflection-[id].md`.

## Return to `/dr-archive`

On successful completion, control returns to `/dr-archive` Step 1 (archive-area determination). The reflection document path and the follow-up-task list become inputs to Steps 2 and 4 respectively.

## Historical note

Prior to Datarim v1.10.0, this logic was a standalone command `/dr-reflect` — an optional pipeline stage between `/dr-compliance` and `/dr-archive`. It was consolidated into `/dr-archive` as mandatory Step 0.5 because the "optional mandatory gate" was the anti-pattern: reflection was expected every task yet trivially skippable. The command was removed; the workflow lives here as a skill.
