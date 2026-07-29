---
task_id: TUNE-0530
artifact: plan
captured_at: 2026-07-29
captured_by: /dr-plan
agent: planner
status: canonical
complexity: L3
parent_prd: ../prd/PRD-TUNE-0530.md
---

# TUNE-0530 — Implementation Plan

## Overview

Rework `skills/tech-stack/SKILL.md` from a prescriptive "Project Type → Required Stack" table into a **guidance-first reference catalog with a stack-proposal mechanism** wired into `/dr-prd` and `/dr-plan`. The operator receives 2-3 viable candidates with explicit trade-offs and a recommendation — not a single mandated answer. The chosen stack is recorded as an ADR and bound by the immutability contract.

**Design:** Approach C (Guidance-First Table + Proposal Step + Defaults for Routine Work) from PRD-TUNE-0530.
**PRD:** `datarim/prd/PRD-TUNE-0530.md` · 10 V-ACs across 5 D-REQs.

## Security Summary

- **Attack Surface:** No new network listeners, no credential handling, no user-data processing. This is a documentation-and-wiring change within the framework runtime.
- **Supply Chain:** No new dependencies introduced. The rework touches only existing `.md` and `.bats` files.
- **Risk:** Low. Content-only change. The worst-case failure mode is an agent receiving no stack guidance (if the rework is broken) or receiving bad guidance (if the research is wrong). Mitigated by bats tests asserting mandatory proposal shape and by the validation dry-run.

## Architecture Impact

| File | Change | Class |
|------|--------|-------|
| `skills/tech-stack/SKILL.md` | Full rework: prescriptive table → guidance catalog + decision method + proposal template | Modified |
| `skills/evolution/stack-agnostic-gate.md` | Update whitelist rationale for tech-stack entry (line 61) | Modified |
| `commands/dr-prd.md` | Add stack-proposal step (§ after discovery interview) with trigger classifier | Modified |
| `commands/dr-plan.md` | Add stack-proposal step (§ Phase 4) with trigger classifier | Modified |
| `agents/architect.md` | Update tech-stack loading description (line 30) | Modified |
| `agents/planner.md` | Update tech-stack loading description (line 32) | Modified |
| `agents/devops.md` | No change needed (loads for "Stack selection guidance" — still accurate) | Unchanged |
| `agents/researcher.md` | No change needed (loads "when evaluating technology choices") | Unchanged |
| `commands/dr-init.md` | Update line 173: "identify required stack" → "generate stack proposal with alternatives" | Modified |
| `skills/visual-maps/` | Update decision-tree diagram reference if tech-stack flow changes | Modified (if present) |
| `tests/` | New bats tests for proposal shape and trigger behaviour | New |

## Component Breakdown

### P1: Rework `skills/tech-stack/SKILL.md`

1. Replace `## Project Type -> Required Stack` with `## Starting Points & Alternatives`
2. Restructure each row: Default Recommendation | Viable Alternatives | When to Reconsider
3. Add 5 new domains: Cross-Platform CLI, Desktop Application, Systems Daemon/Service, Data/ML Pipeline, WASM Module
4. Soften "Mandatory Toolchains" → "Recommended Toolchains"
5. Soften "Architecture Rules" → "Architecture Guidance" with rationale per rule
6. Replace "Final Rule" (anti-choice mandate) with guidance-first framing
7. Add `## Decision-Making Method` section (ADR template, weighted criteria, technology radar)
8. Add `## Stack Proposal Template` (the mandatory shape from PRD § Technical Approach § 2)
9. Add `## Trigger Classifier` section (when to run full proposal vs use defaults)
10. Add `## Immutability and Binding` section (ADR records choice; return-to-plan if changed)
11. Update the Mermaid decision tree to reflect trigger-classifier flow

### P2: Resolve Stack-Agnostic Gate Contradiction

1. Update `skills/evolution/stack-agnostic-gate.md` line 61: replace the tech-stack whitelist rationale with "designated technology guidance file; names concrete technologies to give actionable recommendations while presenting alternatives and trade-offs rather than single mandated answers."

### P3: Wire Proposal Step into Commands

1. `commands/dr-prd.md`: Add step after discovery interview — trigger classifier → if "full": generate stack proposal using the template from tech-stack
2. `commands/dr-plan.md`: Add step in Phase 4 — trigger classifier → if "full" and no ADR from PRD: generate proposal; if ADR exists: verify it
3. `commands/dr-init.md`: Update line 173 to reflect guidance-not-prescription language

### P4: Update Agent Loading

1. `agents/architect.md:30` — update description: "generates stack proposals with alternatives and trade-offs"
2. `agents/planner.md:32` — update description: "produces candidate options, not a single mandated answer"

### P5: bats Tests

1. `tests/test-tech-stack-proposal.bats` — new file with:
   - T1: `@test "stack proposal shape — new project trigger emits mandatory sections"` — asserts ≥2 Candidate sections, Trade-off Summary, Recommendation, Operator Decision checklist
   - T2: `@test "trigger classifier — new-project returns full, same-domain returns skip"`
   - T3: `@test "tech-stack SKILL.md — no prescriptive MANDATORY stack assignments remain"` — grep for old patterns
   - T4: `@test "tech-stack SKILL.md — Rust and Go appear as first-class options"`
   - T5: `@test "stack proposal — immutability binding documented"` — grep for ADR/immutability/Return-to-Source

### P6: Validation Dry-Run

1. Apply the new mechanism to the Control Arcana case
2. Produce a stack proposal comparing React+Tailwind vs React+MUI+Emotion for an admin dashboard
3. Document as evidence in the archive/compliance report

### P7: Documentation and Visual Maps

1. Update `skills/visual-maps/` if any diagram references the old tech-stack flow
2. Update `code/datarim/CLAUDE.md` if the skills table or tech-stack description changes
3. Version consistency: `VERSION` bump to 2.59.0

## Implementation Steps

### Phase 1: Foundation (P1 + P2)

**Step 1.1:** Rework `skills/tech-stack/SKILL.md` per P1 items 1-11.
Verifies: V-AC-2, V-AC-9, V-AC-10
Rollback: `git checkout origin/main -- skills/tech-stack/SKILL.md`

**Step 1.2:** Update `skills/evolution/stack-agnostic-gate.md` whitelist rationale.
Verifies: V-AC-5
Rollback: `git checkout origin/main -- skills/evolution/stack-agnostic-gate.md`

### Phase 2: Wiring (P3 + P4)

**Step 2.1:** Wire proposal step into `commands/dr-prd.md`.
Verifies: V-AC-3
Rollback: `git checkout origin/main -- commands/dr-prd.md`

**Step 2.2:** Wire proposal step into `commands/dr-plan.md`.
Verifies: V-AC-3
Rollback: `git checkout origin/main -- commands/dr-plan.md`

**Step 2.3:** Update `commands/dr-init.md` line 173.
Verifies: V-AC-3
Rollback: `git checkout origin/main -- commands/dr-init.md`

**Step 2.4:** Update `agents/architect.md` and `agents/planner.md` loading descriptions.
Verifies: V-AC-4
Rollback: `git checkout origin/main -- agents/architect.md agents/planner.md`

### Phase 3: Tests (P5)

**Step 3.1:** Create `tests/test-tech-stack-proposal.bats` with T1-T5.
Verifies: V-AC-6, V-AC-7
Rollback: `rm tests/test-tech-stack-proposal.bats`

**Step 3.2:** Run bats tests — expect all to pass.
Verifies: V-AC-6, V-AC-7

### Phase 4: Validation Dry-Run (P6)

**Step 4.1:** Produce the Control Arcana dry-run stack proposal.
Verifies: V-AC-8

### Phase 5: Docs and Version (P7)

**Step 5.1:** Update visual maps and CLAUDE.md references if changed.
**Step 5.2:** Bump VERSION to 2.59.0. Run version-consistency fanout.

## Test Plan

### Unit / Structural Tests (bats)

| Test ID | File | What It Asserts |
|---------|------|----------------|
| T1 | `tests/test-tech-stack-proposal.bats` | Stack proposal shape: mandatory sections present |
| T2 | `tests/test-tech-stack-proposal.bats` | Trigger classifier: correct routing for new-project vs same-domain |
| T3 | `tests/test-tech-stack-proposal.bats` | No prescriptive MANDATORY stack assignments remain in tech-stack |
| T4 | `tests/test-tech-stack-proposal.bats` | Rust and Go are first-class options in tech-stack |
| T5 | `tests/test-tech-stack-proposal.bats` | Immutability binding documented in tech-stack |

### Integration Tests

- `/dr-prd` dry-run: invoke with a new-project trigger, verify proposal is generated
- `/dr-plan` dry-run: invoke with existing ADR, verify ADR verification runs
- `/dr-init` dry-run: verify "generate stack proposal" language in new-project flow

### Regression Tests

- Stack-agnostic gate: run `scripts/stack-agnostic-gate.sh` on the reworked `tech-stack/SKILL.md` — must PASS (file is whitelisted)
- Existing bats suite: run full `bats tests/` — no regressions from changed agent/command files
- Shellcheck on any touched `.sh` files

## Rollback Strategy

All changes are in version-controlled framework files under `code/datarim/`. Full rollback: `git checkout origin/main -- <touched-files>`. No database migrations, no deployed services, no irreversible state changes.

Per-file rollback commands listed in each implementation step above.

## Validation Checklist

| V-AC | Check | Verification |
|------|-------|-------------|
| V-AC-1 | Audit table complete | `grep -c "|" datarim/prd/PRD-TUNE-0530.md` — PRD § Context Analysis table rows ≥15 |
| V-AC-2 | Reworked tech-stack meets shape requirements | `grep -c "Starting Points & Alternatives" skills/tech-stack/SKILL.md` = 1; `grep -cE "Cross-Platform CLI|Desktop Application|Systems Daemon|Data/ML Pipeline|WASM Module" skills/tech-stack/SKILL.md` = 5; `grep -c "Rust" skills/tech-stack/SKILL.md` ≥ 3; `grep -c "Go" skills/tech-stack/SKILL.md` ≥ 3 |
| V-AC-3 | Stack-proposal wired into PRD and Plan commands | `grep -n "stack.proposal\|tech-stack\|trigger.classifier" commands/dr-prd.md commands/dr-plan.md commands/dr-init.md` returns ≥1 per file |
| V-AC-4 | Agent loading updated | `grep -n "tech-stack" agents/architect.md agents/planner.md` shows updated descriptions with "alternatives" or "candidate" language |
| V-AC-5 | Gate rationale updated | `grep -A2 "tech-stack" skills/evolution/stack-agnostic-gate.md` shows "designated technology guidance file" in rationale |
| V-AC-6 | Proposal shape test passes | `bats tests/test-tech-stack-proposal.bats` — T1, T3, T5 pass |
| V-AC-7 | Trigger classifier test passes | `bats tests/test-tech-stack-proposal.bats` — T2 passes |
| V-AC-8 | Control Arcana dry-run | Dry-run documented in archive/compliance with ≥2 candidate stacks |
| V-AC-9 | Immutability binding documented | `grep -n "immutability\|ADR\|Return-to-Source\|binding" skills/tech-stack/SKILL.md` returns ≥1 hit |
| V-AC-10 | Decision tree updated | Mermaid diagram in tech-stack contains "trigger" or "proposal" or "classifier" node |

## Decisions

1. **Approach C (Guidance-First Table + Proposal Step) selected** over Approach A (add Alternatives column) and Approach B (remove table entirely). Rationale: preserves the table as a quick-reference default while adding the proposal mechanism for non-routine cases. Recorded in PRD § Solution Exploration.
2. **backend-stack-standards.md not touched.** The ecosystem backend standard is a separate mandate per the operator brief. No change without a consilium verdict and child task.
3. **Mandatory toolchains (uv+ruff+pytest, pnpm+TypeScript+eslint+prettier+vitest) retained as strong recommendations.** These are quality-floor tooling choices, not architecture stack prescriptions. Renamed to "Recommended Toolchains."

No new sibling archives landed since `/dr-init` captured_at 2026-07-29 — architectural-superseding fallback re-check is a no-op.
