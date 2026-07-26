---
task_id: TUNE-0517
artifact: reflection
captured_at: 2026-07-26
captured_by: /dr-compliance
reflection_basis: "be3b82d2dc668456"
---

# Reflection: TUNE-0517 -- Vendor-default model and latest CLI-agent policy

**Date:** 2026-07-26
**Complexity:** Level 2
**Duration:** one autonomous lifecycle

## Summary

Replaced stale model pins with explicit vendor-default intent, documented the
runtime policy boundary, added an optional fail-open CLI version hint, and
closed the task with focused and full regression evidence.

## What Worked Well

- Semantic configuration avoided inventing vendor model identifiers.
- A small opt-in helper reused the existing timeout primitive and preserved the
  selector's control flow.
- Isolated review found three concrete weaknesses before QA: unclear tier
  consumption, an unbounded probe, and false-green test assertions.
- The canonical suite passed 2,086/2,086 after the fixes.

## What Could Be Improved

- `incident_class: provenance_status_flip_fixed_point` -- the provenance helper
  treats the required QA report commit as branch drift, so dogfooding a
  commit-per-status-flip workflow needs explicit re-certification.
- Broad plugin-local test sweeps include platform-specific baseline failures
  outside the canonical gate; the canonical command should remain the primary
  pass/fail evidence.

## Lessons Learned

- Vendor-default policy is safest when configuration records intent and the
  adapter omits an override; a token named `vendor-default` must never be sent
  as though it were a model ID.
- Optional diagnostics need a time bound as well as ignored nonzero exits.
- Multi-assertion Bats tests require every assertion to be terminal or followed
  by `|| return 1`.

## Evolution Proposals

None. The provenance fixed-point incident class was not found in prior
reflections and is recorded for recurrence detection; changing that contract
would be Class B and is not justified by a single occurrence.

## Metrics

- Files changed before lifecycle reports: 10 shipped or test files
- Net task diff at QA: 656 additions, 23 removals across all lifecycle files
- Tests added: 8 focused policy tests
- Issues found by QA/review: 3, all fixed before QA
- Framework inventory: 69 skill entrypoints, 19 agents, 27 commands

## Follow-Up Tasks

None required for TUNE-0517. Framework inventory exceeds the optimization
advisory thresholds; `/dr-optimize` may be run separately when desired.
