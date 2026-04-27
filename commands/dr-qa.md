---
name: dr-qa
description: Multi-layer quality verification — checks PRD alignment, design conformance, plan completeness, and code quality
---

# /dr-qa - Multi-Layer Quality Verification

**Role**: Reviewer Agent
**Source**: `$HOME/.claude/agents/reviewer.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/reviewer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **SKILL**: Read `$HOME/.claude/skills/security.md` and `$HOME/.claude/skills/testing.md`.
5.  **CONTEXT**: Read `datarim/tasks.md` to get the resolved task's implementation plan. Read `datarim/activeContext.md` for current state.
6.  **ACTION**: Execute the 4 verification layers below, in order, based on available artifacts. Skip layers whose artifacts do not exist.
7.  **OUTPUT**: Write `datarim/qa/qa-report-{task-id}.md` with results.

---

## Layer 1: PRD Alignment

**Condition:** Execute only if `datarim/prd/*.md` exists.

**Checks:**
- Read all PRD files for the current task
- Compare each stated requirement against the implementation
- Flag any **missing features** (in PRD but not implemented)
- Flag any **scope creep** (implemented but not in PRD)
- Verify all acceptance criteria from the PRD are satisfied

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 1: PRD Alignment — {VERDICT}

**PRD files reviewed:** {list}

| Requirement | Status | Notes |
|------------|--------|-------|
| R1: {desc} | Implemented / Missing / Partial | {detail} |

**Missing features:** {list or "None"}
**Scope creep:** {list or "None"}
```

---

## Layer 2: Design Conformance

**Condition:** Execute only if `datarim/creative/*.md` exists.

**Checks:**
- Read all creative/design documents for the current task
- Verify architectural decisions (ADRs) are respected in code
- Check that chosen patterns (from design phase) are actually used
- Flag any **deviations** from the approved design
- If deviations exist, assess whether they are improvements or regressions

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 2: Design Conformance — {VERDICT}

**Design docs reviewed:** {list}

| Decision | Status | Notes |
|----------|--------|-------|
| ADR-001: {desc} | Followed / Deviated / N/A | {detail} |

**Deviations:** {list with assessment or "None"}
```

---

## Layer 3: Plan Completeness

**Condition:** Execute only if `datarim/tasks.md` contains implementation steps for the current task.

**Checks:**
- Read the implementation plan from `datarim/tasks.md`
- Verify each planned step was completed
- Flag any **skipped steps** with reason assessment
- Flag any **unplanned steps** that were added during implementation
- Check that step ordering was respected (dependencies honored)

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 3: Plan Completeness — {VERDICT}

| Step | Status | Notes |
|------|--------|-------|
| 1. {desc} | Done / Skipped / Modified | {detail} |

**Skipped steps:** {list with risk assessment or "None"}
**Unplanned additions:** {list or "None"}
```

---

## Layer 4: Code Quality

**Condition:** Always executed.

**Checks:**

### 4a. Tests
- Run the project test suite (detect runner from `package.json`, `Makefile`, `Cargo.toml`, etc.)
- Report: total tests, passed, failed, skipped
- If tests fail, list failures with file and line

### 4b. Security
- Apply checks from `$HOME/.claude/skills/security.md`
- Scan for hardcoded secrets, exposed endpoints, missing input validation
- Check dependency vulnerabilities if lockfile exists (use the project's package-manager-native audit command at the declared severity threshold)

### 4c. Anti-Patterns
- Methods exceeding 50 lines
- Functions with more than 7 parameters
- Duplicated code blocks
- Missing error handling on async operations
- Console.log / print statements left in production code

### 4d. Live Smoke-Test Gate (raw SQL / cross-DB / cross-instance)
- If the changed code uses `$queryRaw`, `raw()`, `sequelize.query()`, or any path that bypasses the ORM type-checker — a **live smoke test** against the actual target datasource is **mandatory**. Mocked/unit tests do not satisfy this gate (see `$HOME/.claude/skills/testing.md` § Live Smoke-Test Gate; reference incident: DEV-1156).
- In multi-datasource projects (e.g. aio-v2: `PrismaService` → `stats` mysql5 vs `PrismaBiService` → `bi_aggregate` mysql8), verify the correct client is injected for the target table. A wrong-client `$queryRaw` compiles clean and fails at runtime.
- **Record in QA report:** the exact smoke-test command, the datasource hit, and the result (row count / expected empty / error). No smoke test ⇒ Layer 4 verdict is **FAIL**, not PASS_WITH_NOTES.

### 4e. Definition of Done
- Read DoD from `datarim/tasks.md` or `datarim/prd/*.md`
- Check each criterion

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 4: Code Quality — {VERDICT}

**Tests:** {X passed, Y failed, Z skipped}
**Security issues:** {count — list if any}
**Anti-patterns:** {count — list if any}

| DoD Criterion | Status |
|--------------|--------|
| {criterion} | Met / Not met |
```

---

## QA Report Template

Write to `datarim/qa/qa-report-{task-id}.md`:

```markdown
# QA Report — {TASK-ID}

**Date:** {YYYY-MM-DD}
**Reviewer:** Reviewer Agent
**Overall Verdict:** {ALL_PASS | CONDITIONAL_PASS | BLOCKED}

---

{Layer 1 section — or "Layer 1: PRD Alignment — SKIPPED (no PRD artifacts)"}

---

{Layer 2 section — or "Layer 2: Design Conformance — SKIPPED (no design artifacts)"}

---

{Layer 3 section — or "Layer 3: Plan Completeness — SKIPPED (no implementation plan)"}

---

{Layer 4 section}

---

## Summary

**Layers executed:** {N of 4}
**Results:** {list of layer verdicts}

## Next Steps

{Based on overall verdict — see routing below}
```

---

## Verdict Logic

### Per-Layer Verdicts

| Verdict | Meaning |
|---------|---------|
| **PASS** | All checks satisfied, no issues |
| **PASS_WITH_NOTES** | All checks satisfied, minor observations that don't block |
| **FAIL** | One or more checks failed, must be addressed |

### Overall Verdict

| Overall | Condition | Next Step |
|---------|-----------|-----------|
| **ALL_PASS** | Every executed layer is PASS | L3-4 → `/dr-compliance`; L1-2 → `/dr-archive` |
| **CONDITIONAL_PASS** | All layers PASS or PASS_WITH_NOTES, no FAIL | L3-4 → `/dr-compliance`; L1-2 → `/dr-archive` (notes documented) |
| **BLOCKED** | One or more layers FAIL | Route by earliest failed layer (see FAIL Routing below) |

---

## Next Steps (CTA)

After verdict, the reviewer agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`. BLOCKED verdicts MUST use the FAIL-Routing variant.

**Routing logic for `/dr-qa`:**

- ALL_PASS or CONDITIONAL_PASS at L3-4 → primary `/dr-compliance {TASK-ID}` (final hardening)
- ALL_PASS or CONDITIONAL_PASS at L1-2 → primary `/dr-archive {TASK-ID}` (notes documented if any)
- **BLOCKED** — FAIL-Routing variant per Layer-to-command map:

| Failed Layer | Return Command (primary in CTA) | Rationale |
|--------------|---------------------------------|-----------|
| Layer 1 (PRD Alignment) | `/dr-prd {TASK-ID}` | Requirements incomplete or wrong — update PRD first |
| Layer 2 (Design Conformance) | `/dr-design {TASK-ID}` | Architecture decisions violated — revise design |
| Layer 3 (Plan Completeness) | `/dr-plan {TASK-ID}` | Steps skipped or plan outdated — update plan |
| Layer 4 (Code Quality) | `/dr-do {TASK-ID}` | Code bugs, security, anti-patterns — fix code |

Multi-layer FAIL: route to **earliest** failed layer (Layer 1 > 2 > 3 > 4). Earlier failures are root causes.

The FAIL-Routing CTA header MUST read: `**QA failed для {TASK-ID} — earliest failed layer: Layer N (Layer name)**`. Variant B menu when >1 active tasks.

## Loop Guard

If the same layer fails **3 times** on the same task, escalate to the user with a summary of all three failures. Options:
- (a) Force-pass with documented waiver (recorded in QA report)
- (b) Reduce task scope
- (c) Cancel the task

## Re-entry After FAIL Fix

After returning to an earlier stage and correcting the issue:
- **Resume forward** through remaining pipeline stages
- **QA must be re-run** — previous pass is invalidated by the correction
- Previous QA report kept for audit trail; new report gets `-v2`, `-v3` suffix

## Transition Checkpoint

Before proceeding to next stage:
```
[ ] All applicable layers executed?
[ ] DoD criteria verified against implementation?
[ ] Security issues addressed (or documented as accepted risk)?
[ ] QA report written to datarim/qa/?
```
