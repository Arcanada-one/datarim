---
id: TUNE-0585
title: Universal customer-delivery contract and gates
status: in_progress
priority: P0
complexity: L4
type: framework
project: Datarim
started: 2026-08-22
parent: null
related: [TALO-0001]
prd: datarim/prd/PRD-TUNE-0585.md
plan: null
---

## Overview

Create a universal Datarim customer-delivery canon that preserves every customer remark, decomposes it into atomic requirements, requires immutable pre-work capability bindings, and derives delivery state from evidence coverage. A customer-facing requirement cannot be satisfied by tools, documentation, or tests alone: it needs a deployed revision, live visitor-visible proof, the required screenshot matrix, and a customer disposition.

This task delivers the framework mechanism only. It is the first dependency in the operator-approved sequence. TALO-0001 will consume the released mechanism in a separate isolated worktree, import the canonical White Paper figures, reconcile all open customer-review requirements, and close the remaining live-site work.

## Acceptance Criteria

- [ ] AC-1: A versioned customer-delivery contract schema maps verbatim remarks to atomic requirement IDs and preserves source provenance.
- [ ] AC-2: Every atomic requirement carries a visitor-visible production AC or an explicit enabling-only parent binding.
- [ ] AC-3: Pre-work role, skill, blueprint, constraint, policy, and success-criterion references are immutable and pinned before implementation begins.
- [ ] AC-4: The validator rejects `Unbound`, mutable refs, missing capability classes, and post-hoc attribution.
- [ ] AC-5: Customer-review inputs cannot enter implementation until a review-to-evolution disposition is recorded and pinned.
- [ ] AC-6: User-facing requirements require RED/GREEN evidence, deployed SHA, live checks, an RU/EN × mobile/desktop × light/dark screenshot matrix, and customer disposition.
- [ ] AC-7: Tools, docs, static checks, and implementation completion can support but never satisfy a user-facing requirement.
- [ ] AC-8: Epic state is computed from atomic coverage; stored or narrated `complete` state cannot override uncovered requirements.
- [ ] AC-9: `/dr-init`, `/dr-prd`, `/dr-plan`, `/dr-design`, `/dr-do`, `/dr-qa`, `/dr-compliance`, `/dr-archive`, and `/dr-auto` carry the appropriate capture/pre-work/evidence/close gates.
- [ ] AC-10: The framework ships templates, reference documentation, migration rules, focused RED/GREEN tests, full validation, independent spec review, and independent quality review.

## Constraints

- Preserve existing init-task and expectations semantics; do not overload a human wish with machine delivery state.
- English-only for shipped framework surfaces.
- Backward compatibility must be explicit and time-bounded; new customer-facing tasks fail closed.
- No project-specific Talomnia logic in the universal validator.
- No post-hoc knowledge attribution, mutable `main`/`latest` references, or self-certified customer acceptance.
- Protected branches receive changes only through the normal PR path.
- Operator-only approvals, signatures, legal sign-off, production payments, and public posts remain hard gates.

## Out of Scope

- Talomnia requirement import, product implementation, deployment, or customer acceptance; those follow after this framework task lands.
- Merging Talomnia Knowledge PR #44, which remains the operator's signature act.
- Replacing the existing expectations checklist or init-task append-log.
- A project-specific knowledge-graph implementation inside Datarim.

## Related

- TALO-0001 — first consumer and downstream live-delivery epic.
- `skills/init-task-persistence/SKILL.md` — verbatim operator intent.
- `skills/expectations-checklist/SKILL.md` — human acceptance wishes.
- `commands/dr-qa.md`, `commands/dr-compliance.md`, `commands/dr-archive.md` — verification and closure consumers.

## Implementation Notes

- Exact baseline: `origin/main` at `d27b15f`; `./validate.sh` exited 0 before task artifacts were written.
- Isolated worktree: `/home/dev/.worktrees/datarim/TUNE-0585-customer-delivery`.
- Coworker drafting was not retried because the configured provider previously failed non-retryably with `401 User not found`; native drafting is the documented fallback for this turn.
- The approved architecture is a dedicated machine-readable delivery contract plus deterministic validator and lifecycle hooks. Existing expectations remain the human-readable acceptance layer.
