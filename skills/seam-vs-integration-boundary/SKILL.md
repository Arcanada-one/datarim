---
name: seam-vs-integration-boundary
description: "Pattern guidance: flag L3+ backlog one-liners that mix a seam/contract concern with an integration/call-site concern; loaded by /dr-prd and /dr-plan."
---

A backlog one-liner must not bundle two discrete module concerns under one task ID. When it does, the task is a foundation task plus an integration follow-up wearing a single ID, and the integration half tends to surface as out-of-scope late — at `/dr-qa` — and get deferred as a carry-forward note.

## Pattern

Two concern-classes recur together in one-liners that should have been split:

- **Seam / contract concern** — define an abstraction inside one module: an interface, contract, protocol, state machine, or dispatcher. Its acceptance is a shape/compile assertion inside that module.
- **Integration / call-site concern** — wire that seam into a caller: a command-line flag, a call site, an end-to-end path, propagation into a downstream module. Its acceptance is a behavioural assertion across the module boundary.

When a single L3+ one-liner contains both classes, flag the operator before component breakdown to either:

1. **Split** into a foundation task (the seam) plus an integration follow-up (the call site), or
2. **Scope the ACs** so the integration is explicitly optional/deferred — the seam task's acceptance covers only the in-module contract, and a named follow-up owns the wiring.

## Why

The two concerns have different evidence chains and different done-definitions. The seam is done when it builds and its in-module tests pass; the integration is done when a caller in another module observably uses it. Folding them into one one-liner hides the boundary: the plan sizes the seam, TDD turns the seam green, `/dr-qa` passes on the seam — and only then does the un-wired integration surface as an out-of-scope gap. A retrospective on a foundation task captured this exactly: the one-liner mixed an interface + dispatcher seam with its command-line-flag wiring; the wiring was noticed only at `/dr-qa` Layer 1 and had to be deferred to a follow-up task. Sizing the boundary at plan time absorbs the split into the plan rather than discovering it inside `/dr-qa`.

## How to apply

1. For every L3+ task, read the backlog one-liner and classify its concerns. A seam concern names an in-module abstraction to define; an integration concern names a caller to wire it into.
2. If both classes are present, do not proceed straight to component breakdown. Flag the operator with the two-way choice above (split vs explicit AC scoping) and record the decision in the plan's Overview / Decisions section.
3. As a mechanical aid, run the advisory scanner over the one-liner:
   ```
   dev-tools/check-seam-integration-boundary.sh --task {TASK-ID} --report
   ```
   It flags a co-occurrence of seam-class and integration-class signals. It is **advisory only** — never a hard block. The scanner's two signal lists are a floor, not a ceiling: it can miss a mix worded outside the lists, and it can false-positive on a genuine single-concern one-liner that incidentally carries one word from each list. The planner makes the final call; the scanner only surfaces candidates.
4. When the task is split, the follow-up integration task gets its own backlog entry with its own acceptance. When the ACs are scoped instead, the seam task's acceptance must name the deferred integration and point at the follow-up so the boundary is falsifiable rather than implicit.

## Relationship to v-ac-axis-split

`v-ac-axis-split` splits a single V-AC group that mixes a deterministic axis with a statistical axis — a split of one acceptance criterion by *evidence kind*. This skill splits a single task one-liner that mixes a seam concern with an integration concern — a split of one task by *module boundary*. Both are plan-time "split before you finalise" rules; they apply independently and can both fire on the same task.
