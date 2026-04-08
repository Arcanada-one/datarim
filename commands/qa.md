---
name: qa
description: Multi-layer quality verification — checks PRD alignment, design conformance, plan completeness, and code quality
---

# /qa - Multi-Layer Quality Verification

**Role**: Reviewer Agent
**Source**: `$HOME/.claude/agents/reviewer.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/reviewer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/init`. Do NOT create it — only `/init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.
3.  **SKILL**: Read `$HOME/.claude/skills/security.md` and `$HOME/.claude/skills/testing.md`.
4.  **CONTEXT**: Read `datarim/tasks.md` to get the current task ID and implementation plan. Read `datarim/activeContext.md` for current state.
5.  **ACTION**: Execute the 4 verification layers below, in order, based on available artifacts. Skip layers whose artifacts do not exist.
6.  **OUTPUT**: Write `datarim/qa/qa-report-{task-id}.md` with results.

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
- Check dependency vulnerabilities if lockfile exists (`npm audit`, `pip audit`, `cargo audit`)

### 4c. Anti-Patterns
- Methods exceeding 50 lines
- Functions with more than 7 parameters
- Duplicated code blocks
- Missing error handling on async operations
- Console.log / print statements left in production code

### 4d. Definition of Done
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
| **ALL_PASS** | Every executed layer is PASS | Proceed to `/compliance` or `/reflect` |
| **CONDITIONAL_PASS** | All layers PASS or PASS_WITH_NOTES, no FAIL | Proceed to `/compliance` or `/reflect`, notes documented |
| **BLOCKED** | One or more layers FAIL | Return to `/do` with fix list from failed layers |

---

## Next Steps

- **ALL_PASS or CONDITIONAL_PASS** at L3-4 → `/compliance`
- **ALL_PASS or CONDITIONAL_PASS** at L1-2 → `/reflect`
- **BLOCKED** → `/do` with specific fix list extracted from FAIL layers
