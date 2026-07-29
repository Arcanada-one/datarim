---
task_id: TUNE-0530
artifact: task-description
schema_version: 1
captured_at: 2026-07-29
captured_by: /dr-plan
agent: planner
status: canonical
complexity: L3
priority: P1
plan: plans/TUNE-0530-plan.md
prd: ../prd/PRD-TUNE-0530.md
---

# TUNE-0530 — Rework stack selection: from prescribed stacks to justified proposals

## Overview

Rework Datarim's tech-stack selection from a prescriptive "Project Type → Required Stack" table into a mechanism that produces **2-3 viable candidate stacks with explicit trade-offs and a recommendation** at PRD/plan time. The operator chooses; the framework records the choice ADR-style and enforces it downstream via the immutability/return-to-plan contract.

**Complexity:** L3 · **Priority:** P1 · **Status:** in_progress

## Related

- **PRD:** `datarim/prd/PRD-TUNE-0530.md` — full problem statement, audit, solution exploration, research sweep
- **Plan:** `datarim/plans/TUNE-0530-plan.md` — phased implementation, component breakdown, validation checklist
- **Init-task:** `datarim/tasks/TUNE-0530-init-task.md` — operator's verbatim brief
- **Expectations:** `datarim/tasks/TUNE-0530-expectations.md` — operator wishlist (5 items)

## Architecture Impact

- `skills/tech-stack/SKILL.md` — full rework: prescriptive table → guidance catalog + proposal mechanism
- `skills/evolution/stack-agnostic-gate.md` — update whitelist rationale (line 61)
- `commands/dr-prd.md` — wire stack-proposal step with trigger classifier
- `commands/dr-plan.md` — wire stack-proposal / ADR-verification step
- `commands/dr-init.md` — update line 173 language
- `agents/architect.md`, `agents/planner.md` — update tech-stack loading descriptions
- `tests/test-tech-stack-proposal.bats` — new bats tests (T1-T5)
- New domains: cross-platform CLI/desktop, systems services, data/ML pipeline, WASM

## Implementation Steps

See `datarim/plans/TUNE-0530-plan.md` § Implementation Steps — 5 phases: Foundation, Wiring, Tests, Validation Dry-Run, Docs/Version.

## Test Plan

See `datarim/plans/TUNE-0530-plan.md` § Test Plan — 5 bats tests + integration dry-runs + regression.

## Rollback Strategy

`git checkout origin/main -- <touched-files>` for all changes. No irreversible state.

## Validation Checklist

See `datarim/plans/TUNE-0530-plan.md` § Validation Checklist — 10 V-AC rows.

## Implementation Notes

**2026-07-29 · /dr-do · Phases 1-5 complete.**

### Phase 1: Foundation — `skills/tech-stack/SKILL.md` fully reworked
- Replaced "Project Type -> Required Stack" with "Starting Points & Alternatives" (3-column format)
- Added 5 new domains: Cross-Platform CLI, Desktop, Systems Daemon, Data/ML Pipeline, WASM
- Added Trigger Classifier (6 signals + default catch-all), Stack Proposal Template (10 factors), Decision-Making Method, Immutability and Binding with escape sequence + Security-Emergency Fast-Track
- All 15 consilium design decisions (D-1 through D-15) incorporated

### Phase 2: Gate — `skills/evolution/stack-agnostic-gate.md` whitelist rationale updated

### Phase 3: Commands — `dr-prd.md` Step 2.5, `dr-plan.md` Step 6, `dr-init.md` line 173 wired

### Phase 4: Agents — `architect.md`, `planner.md` loading descriptions updated

### Phase 5: bats tests — `tests/test-tech-stack-proposal.bats` (10 tests, all pass)

### Phase 6: Validation dry-run — `datarim/tasks/TUNE-0530-validation-dry-run.md` (Control Arcana: 3 candidates, V-AC-8 satisfied)

### Evidence:
- Evidence: V-AC-1 — audit in PRD § Context Analysis
- Evidence: V-AC-2 — `grep "Starting Points & Alternatives" skills/tech-stack/SKILL.md` = 1; new domains: 5; Rust: ≥3 rows; Go: ≥3 rows
- Evidence: V-AC-3 — `grep "stack.proposal\|tech-stack\|Trigger Classifier" commands/dr-prd.md commands/dr-plan.md commands/dr-init.md` returns ≥1 per file
- Evidence: V-AC-4 — `grep "tech-stack" agents/architect.md agents/planner.md` shows updated descriptions
- Evidence: V-AC-5 — `grep "tech-stack" skills/evolution/stack-agnostic-gate.md` shows "designated technology guidance file"
- Evidence: V-AC-6 — `bats tests/test-tech-stack-proposal.bats` T1, T3, T5 all pass
- Evidence: V-AC-7 — `bats tests/test-tech-stack-proposal.bats` T2 passes
- Evidence: V-AC-8 — `datarim/tasks/TUNE-0530-validation-dry-run.md` — 3 candidates with trade-offs
- Evidence: V-AC-9 — `grep "immutability\|ADR\|Return-to-Source\|binding" skills/tech-stack/SKILL.md` returns ≥1 hit
- Evidence: V-AC-10 — Mermaid diagram in tech-stack contains "Trigger Classifier" node
