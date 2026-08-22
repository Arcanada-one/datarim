---
id: PRD-TUNE-0585
title: Universal customer-delivery canon
status: approved
version: 1.0
created: 2026-08-22
author: Codex under operator-approved autonomous execution
---

# PRD-TUNE-0585 — Universal Customer-Delivery Canon

## Context

Datarim already preserves the operator's verbatim brief in `init-task.md`, translates it into human wishes in `expectations.md`, and verifies implementation through PRD, plan, QA, compliance, and archive stages. The current contracts do not prove that a customer remark became a delivered customer outcome. In particular, `pending` expectations can pass verification, production proof is armed only for selected deploy-class tasks, and an implementation artifact can be described as complete without a complete atomic chain back to the customer remark.

Talomnia exposed the consequence at epic scale: review findings produced tools, documents, and checks while customer-visible design and White Paper requirements could remain open or be rediscovered. The framework needs a universal contract before Talomnia is reconciled again.

## Problem

The pipeline lacks a machine-verifiable chain from customer language to live delivery. It therefore cannot answer, without narrative judgment:

1. Was every verbatim customer remark preserved?
2. Was each remark decomposed into atomic requirements?
3. Did each requirement have an honest visitor-visible production AC?
4. Were all required capabilities pinned before work began?
5. Did customer review cause knowledge evolution before remediation?
6. Can the tests detect absence or regression?
7. Which exact revision is deployed, and what does a visitor see?
8. Did the customer accept, return, defer, or reject the result?
9. Is the epic complete by coverage rather than by a stored status word?

## Goals

- Add one universal, versioned customer-delivery contract usable by every Datarim-managed project.
- Preserve the init-task and expectations contracts as distinct human-intent layers.
- Enforce pre-work capability binding and review-to-evolution before implementation.
- Enforce live evidence for visitor-visible work and reject artifact-only self-certification.
- Derive task and epic delivery state from source and evidence coverage.
- Provide deterministic validation, actionable missing-ID output, templates, migration guidance, and lifecycle wiring.
- Dogfood the contract in TUNE-0585 before registering Talomnia as the first external consumer.

## Non-Goals

- Implement a universal knowledge graph or require one storage backend.
- Infer whether a customer likes a result; disposition must come from a customer-authority record.
- Merge operator-signature or legal-approval artifacts automatically.
- Perform the downstream Talomnia content/design work inside the framework repository.
- Replace existing PRD V-AC, expectations, mutation, CI, deploy, or archive gates.

## Solution Approaches

### Approach A — Dedicated JSON delivery contract plus deterministic validator (selected)

Add `datarim/tasks/{TASK-ID}-customer-delivery.json` as the machine source of truth. A standard-library Python validator checks schema, source coverage, pre-work binding order, evidence completeness, screenshot coverage, customer disposition, and derived epic state. Commands consume the same validator at phase-specific gates.

Advantages: clean separation from human wishes; safe verbatim strings; deterministic cross-task coverage; direct adoption by non-Markdown projects; exact missing requirement IDs. Trade-off: one additional per-task artifact and validator.

### Approach B — Expectations schema v4

Add all delivery fields to each expectation item. This reduces file count but conflates human wishes with atomic requirements, cannot naturally represent one remark mapping to several requirements, and makes the existing Markdown parser materially more fragile.

### Approach C — Archive checklist only

Require a prose delivery table at archive. This is cheap but post-hoc by construction, cannot block implementation without pinned capabilities, and repeats the failure class the task exists to remove.

## Selected Architecture

### 1. Artifact

`datarim/tasks/{TASK-ID}-customer-delivery.json` is a versioned JSON object with four top-level collections:

- `remarks[]`: stable `remark_id`, verbatim text, immutable source locator/digest, customer authority, and mapped requirement IDs.
- `requirements[]`: stable `requirement_id`, class (`visitor-visible` or `enabling`), parent relationship, visitor AC, target surfaces, pre-work capability binding, evolution disposition, implementation references, RED/GREEN evidence, deployment/live evidence, screenshot evidence, and customer disposition.
- `children[]`: child task IDs and contract paths for umbrella/epic aggregation.
- `policy`: schema version, task/epic identity, legacy disposition, and project registration reference.

Derived delivery state is never authoritative data in the artifact. The validator calculates it from coverage each run.

### 2. Atomic identity and source coverage

`remark_id` and `requirement_id` are immutable within a task. Every remark maps to at least one requirement. Every requirement maps back to at least one remark. Duplicate verbatim remarks may share a source digest but retain distinct source locators. A one-to-many decomposition is explicit.

### 3. Requirement classes

- `visitor-visible`: must carry a production route/surface and the complete live proof chain.
- `enabling`: may close on its own implementation evidence only when it names a visitor-visible parent requirement. It never marks the parent delivered.

This permits tooling and infrastructure tasks to close honestly without allowing them to satisfy customer-facing work.

### 4. Pre-work binding

Before implementation starts, every requirement must pin exactly one or more immutable references for each class: role, skill, blueprint, constraint, policy, and success criterion. Each reference carries a logical ID, immutable revision, content digest, binding record locator, binding commit, and `pinned_at` timestamp. The validator rejects:

- literal or semantic `Unbound`;
- mutable revisions such as `main`, `master`, `latest`, branch-only URLs, or unversioned paths;
- any missing capability class;
- a binding commit that is not an ancestor of the first implementation commit when both are in the same repository;
- a binding timestamp after implementation started;
- an evolution disposition written after implementation started.

### 5. Review-to-evolution gate

Every requirement sourced from a customer review must record one pre-work disposition:

- `reused`: existing pinned artifacts already cover the requirement;
- `revised`: one or more existing artifacts were revised and pinned;
- `created`: missing artifacts were created and pinned;
- `no-change`: explicit finding that no evolution is needed, with pinned covering artifacts and a reason.

The pre-work gate blocks `/dr-do` when the disposition or immutable references are absent. Writing an evolution note after implementation does not clear the gate.

### 6. Evidence model

Every requirement needs load-bearing RED and GREEN records naming command/test, exit code, artifact digest, and captured evidence path. For `visitor-visible` requirements the close gate additionally requires:

- exact merged and deployed SHA, with equality or an explicit build-provenance link;
- live URL/probe evidence captured after deployment;
- eight screenshot cells: RU and EN × mobile and desktop × light and dark;
- screenshot file digest, viewport, theme, locale, URL, deployed SHA, and timestamp for every cell;
- customer disposition: `accepted`, `returned`, `deferred`, or `rejected`, with immutable authority/source locator.

Tests, tools, source documents, CI, and local screenshots are supporting evidence. None can substitute for the deployed/live/screenshot/disposition chain of a visitor-visible requirement.

### 7. Derived coverage

The validator reports deterministic counts and exact missing IDs for:

- remark-to-requirement coverage;
- visitor-AC coverage;
- pre-work capability coverage;
- review-to-evolution coverage;
- implementation and RED/GREEN coverage;
- deployment/live coverage;
- screenshot-cell coverage;
- customer-disposition coverage;
- child-contract coverage for epics.

Task delivery is complete only when all in-scope requirements pass. Epic delivery is complete only when its own requirements and every registered child contract pass. A stored `completed` status cannot override a failing derived report.

### 8. Lifecycle wiring

- `/dr-init`: create the contract skeleton and capture the initial verbatim remark set.
- `/dr-prd`: atomize remarks, add visitor ACs/classes, and bind requirements to V-AC.
- `/dr-plan` and `/dr-design`: pin all capability and evolution references before implementation.
- `/dr-do`: run pre-work validation before source edits; append implementation and RED/GREEN evidence after work.
- `/dr-qa`: verify implementation evidence and, for deployed work, the live matrix without accepting artifact-only completion.
- `/dr-compliance`: hard-enforce contract and coverage completeness for the task's declared delivery stage.
- `/dr-archive`: require derived complete state; unresolved visitor requirements block archive unless the customer disposition is an operator-authorized `deferred` with a durable follow-up.
- `/dr-auto`: choose the next reversible action from exact missing requirement IDs, never from narrated epic status.

### 9. Project registration

The framework ships a project-registration template. Consumers register project ID, epic root, contract roots, public surface base URLs, locale/viewport/theme matrices, knowledge-reference resolver, deployment provenance probe, and customer-authority policy. The universal validator accepts adapters but keeps the core schema project-agnostic.

## Requirements

### D-REQ-01: Atomic source mapping

Every nonempty verbatim customer remark has a stable source digest and at least one atomic requirement ID; every requirement has at least one remark ID. Duplicate IDs, dangling mappings, empty verbatim text, or source-digest mismatch block all later phases.

### D-REQ-02: Visitor-visible AC or enabling parent

Every requirement declares exactly one class. `visitor-visible` requires a concrete observable production outcome and target routes/surfaces. `enabling` requires a valid visitor-visible parent and cannot contribute delivered coverage to that parent.

### D-REQ-03: Immutable pre-work capability bindings

Role, skill, blueprint, constraint, policy, and success criterion are all pinned with immutable revision and digest before implementation. Any `Unbound`, mutable reference, missing class, non-ancestor same-repo binding, or later timestamp is a hard failure.

### D-REQ-04: Review-to-evolution

Customer-review requirements carry a pre-work evolution disposition and pinned artifacts. The pre-work gate goes RED when the disposition is absent or post-hoc and GREEN only when the requirement is covered before implementation.

### D-REQ-05: RED/GREEN evidence integrity

Each requirement carries distinct load-bearing RED and GREEN records. Evidence records include command/test identity, exit code, artifact digest, timestamp, and retained path. Identical/vacuous evidence, missing mutation assertion, or missing retained artifact blocks completion.

### D-REQ-06: Visitor-visible live delivery

A visitor-visible requirement is incomplete without exact deployment provenance, a post-deploy live probe, all eight screenshot cells, and customer disposition. Static or local artifacts cannot satisfy this requirement.

### D-REQ-07: Derived task and epic state

Coverage is computed from source mappings, requirements, child contracts, and evidence. The command emits machine-readable JSON and human-readable summaries with exact missing IDs. No stored completion field is accepted as authority.

### D-REQ-08: Phase-specific command gates

The nine lifecycle commands invoke the validator at the appropriate phase and fail closed on invalid contracts. Wiring tests verify every command token and forbid stale/partial integration.

### D-REQ-09: Compatibility and migration

New L1-L4 tasks create the contract by default after the release pivot. Pre-pivot tasks are advisory unless explicitly registered for strict adoption. Once registered strict, a task cannot revert to legacy mode. A migration helper creates a skeleton but never invents customer remarks, bindings, evidence, or dispositions.

### D-REQ-10: Security and evidence preservation

Verbatim external text is treated as data, never executed. CLI text inputs use files or JSON stdin, paths are root-confined, digests are recomputed, symlinks cannot escape the project root, and reports never print secrets. Evidence paths are durable and project-relative; `/tmp` cannot satisfy retention.

### D-REQ-11: Project registration and adapter boundary

The core validator remains project-agnostic. A registration schema defines exact contract roots, surface matrices, adapter commands, and customer authority. Missing or non-executable adapters fail only the phases that need them.

### D-REQ-12: Dogfood and independent reviews

TUNE-0585 has its own valid delivery contract, captures RED before implementation, passes focused and full suites, and receives a subordinate Codex spec review before source work and quality review after implementation.

## Validation Acceptance Criteria

- **V-AC-1 — Atomic coverage:** broken one-to-one, one-to-many, duplicate, dangling, and digest fixtures fail; valid mappings pass. Covers D-REQ-01 and D-REQ-02.
- **V-AC-2 — Pre-work gate:** one mutation per capability class plus `Unbound`, mutable ref, post-hoc timestamp, and ancestry mutants fail; fully pinned fixture passes. Covers D-REQ-03.
- **V-AC-3 — Review evolution:** missing, unpinned, and post-hoc dispositions fail; reused/revised/created/no-change controls pass. Covers D-REQ-04.
- **V-AC-4 — Live close gate:** omitting each RED/GREEN, deploy, live, screenshot-cell, and disposition field fails independently; artifact-only completion remains RED. Covers D-REQ-05 and D-REQ-06.
- **V-AC-5 — Derived epic coverage:** uncovered remark, uncovered child, enabling-only child, and narrated-complete mutants fail with exact IDs; complete graph passes. Covers D-REQ-07.
- **V-AC-6 — Universal wiring and safety:** all lifecycle command hooks, migration behavior, path confinement, digest checks, English-only surface, full validation, and independent reviews pass. Covers D-REQ-08 through D-REQ-12.

## Error Handling

The validator uses stable exit codes: `0` phase satisfied, `1` contract/coverage finding, `2` usage or unreadable input, `3` adapter unavailable for a required phase. Findings include task ID, requirement ID, field/code, and remediation phase. Unknown schema versions and unknown enum values fail closed.

## Rollout

1. Ship and release the universal framework mechanism through a protected PR.
2. Register TALO-0001 in an isolated Arcanada/Talomnia adoption task.
3. Import all customer remarks and canonical White Paper figures without inventing evidence.
4. Derive exact open requirement IDs.
5. Execute reversible Talomnia work requirement-by-requirement.
6. Deploy exact merged revisions, capture the live matrix, and record customer dispositions.

## Risks

- **False completeness through adapters:** adapters provide evidence but cannot set derived state; the core recomputes coverage.
- **Post-hoc timestamps:** same-repo ancestry and retained binding records are authoritative; timestamps alone never prove ordering.
- **Artifact explosion:** one task-level JSON file and retained evidence directories keep the model bounded.
- **Legacy noise:** the pivot is default-strict for new tasks and opt-in strict for pre-pivot tasks.
- **Customer authority ambiguity:** registration names accepted authority kinds; agents cannot author `accepted` dispositions unless explicitly authorized.

## Downstream Boundary

This PRD is complete when the universal mechanism is released. It does not claim that Talomnia is delivered. TALO-0001 remains open until its imported requirement graph, sixteen canonical White Paper figures, product implementation, exact deployment, live screenshot matrix, and customer dispositions pass the new derived coverage gate.
