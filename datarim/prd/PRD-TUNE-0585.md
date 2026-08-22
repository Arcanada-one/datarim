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

### Approach A — Append-only JSONL delivery ledger plus deterministic writer and validator (selected)

Add `datarim/delivery/{TASK-ID}.jsonl` as the machine source of truth. A standard-library Python writer atomically appends hash-chained events; a read-only validator checks schema, source coverage, temporal ordering, evidence completeness, screenshot coverage, customer disposition, and derived epic state. Commands consume the same validator at phase-specific gates.

Advantages: clean separation from human wishes; safe verbatim strings; correction without history rewriting; deterministic cross-task coverage; direct adoption by non-Markdown projects; exact missing requirement IDs. Trade-off: one additional per-task artifact plus a writer and validator.

### Approach B — Expectations schema v4

Add all delivery fields to each expectation item. This reduces file count but conflates human wishes with atomic requirements, cannot naturally represent one remark mapping to several requirements, and makes the existing Markdown parser materially more fragile.

### Approach C — Archive checklist only

Require a prose delivery table at archive. This is cheap but post-hoc by construction, cannot block implementation without pinned capabilities, and repeats the failure class the task exists to remove.

## Selected Architecture

### 1. Artifact

`datarim/delivery/{TASK-ID}.jsonl` is a versioned append-only event stream. Each line carries `schema_version`, `event_id`, `event_type`, `task_id`, `recorded_at`, `payload`, `prev_event_hash`, and `event_hash`. Writers take a per-task lock, recompute the predecessor hash, write to a temporary file, validate the full stream, and atomically replace the ledger. Corrections append a superseding event; no event is edited or deleted.

Normative event types are `lane_classified`, `source_manifest_bound`, `remark_captured`, `requirement_declared`, `production_ac_declared`, `evolution_disposition`, `prework_contract_frozen`, `implementation_authorized`, `implementation_bound`, `red_observed`, `green_observed`, `production_deployment_observed`, `visual_observation`, `customer_disposition`, `child_manifest_bound`, and `event_superseded`.

Derived delivery state is never authored as an authoritative event. The validator calculates it from the current non-superseded event graph every run.

### 2. Atomic identity and source coverage

`remark_id` and `requirement_id` are immutable within a task. Every remark maps to at least one requirement. Every requirement maps back to at least one remark. Duplicate verbatim remarks may share a content digest but retain distinct source locators. A one-to-many decomposition is explicit. For an armed lane, a missing genuine source blocks: agent-authored Overview prose can be retained only as `legacy_unverified_source`, never as `verbatim` customer provenance.

The denominator is not the ledger's self-declared `remark_captured` set. `source_manifest_bound` pins an authoritative, provider-produced inventory of complete source containers and stable item identifiers: the init-task brief and append-log records for native tasks, plus the project registration's issue/comment/document adapters for imported work. The validator independently resolves every manifest item, recomputes its bytes and digest, and rejects uncaptured, multiply captured, missing, or extra source items. A source manifest is valid only when the adapter proves pagination/exhaustion and the manifest is retained at an immutable revision. Semantic atomization is then independently reviewed: a single source item may produce several requirements, but it cannot disappear through aggregation.

### 3. Delivery lanes and surface blueprints

- `customer-visible-v1`: requirements must carry a production route/surface and the complete live proof chain.
- `enabling-v1`: requirements may close on their own implementation evidence only when they name a customer-visible parent requirement in an authoritative manifest. They never mark the parent delivered.
- `none`: the task contains no customer-delivery requirement. It records a reason and cannot be used for a task whose init-task or append-log contains a customer remark or visitor-facing outcome.

Every task classifies its lane, so the canon is universal. The expensive production matrix is hard only where semantics require it, which permits private research, legal, documentation, API, CLI, framework, and tooling work to close honestly without allowing it to satisfy customer-facing work.

Each customer-visible requirement names a pinned surface blueprint with typed executable predicates. `bilingual-web-v1` requires the exact RU/EN × mobile/desktop × light/dark eight-cell matrix and may be widened but not narrowed by registration. Other shipped blueprints define equivalent visitor-observation dimensions for native, CLI, API, and published-document surfaces; none permits tools, source documents, tests, or local-only output to substitute for the actual customer-consumed production surface. Talomnia uses `bilingual-web-v1`.

Atomicity is structural and independently reviewed: one requirement has one subject, one observable behavior, one terminal disposition, and one surface blueprint; its production AC is a typed predicate plus expected value, not prose alone. A source item that contains conjunctions, multiple routes, or independently rejectable outcomes must decompose. The spec review records approved source-item-to-requirement cardinality and fails aggregate catch-all requirements.

### 4. Pre-work binding

Before implementation starts, every armed requirement must pin exactly one or more immutable references for each class: role, skill, blueprint, constraint, policy, and success criterion. Each reference carries a logical ID, immutable revision, content digest, binding record locator, and binding commit. `prework_contract_frozen` names the contract-repository commit that contains the complete binding event. `implementation_authorized` names the exact clean implementation-repository base SHA and a delivery-authorization marker committed in that repository before source changes. The first implementation commit must descend from that marker commit. The validator rejects:

- literal or semantic `Unbound`;
- mutable revisions such as `main`, `master`, `latest`, branch-only URLs, or unversioned paths;
- any missing capability class;
- a contract freeze commit that does not predate the implementation authorization;
- a claimed freeze event absent from the ledger blob at the binding commit;
- a missing authorization marker, dirty-worktree inventory, mismatched target-repository identity/base SHA, or implementation commit that is not a descendant of the marker commit;
- an evolution disposition written after `implementation_bound`.

Timestamps are descriptive, not ordering authority. Event order, hash-chain integrity, retained ledger blobs, the committed authorization marker, and implementation-repository Git ancestry establish the auditable ordering contract. The framework cannot prove the absence of deliberately hidden off-ledger work; such bypass is a detectable policy violation and cannot be imported later as canon-compliant pre-work.

### 5. Review-to-evolution gate

Every requirement sourced from a customer review must record one pre-work disposition:

- `reused`: existing pinned artifacts already cover the requirement;
- `revised`: one or more existing artifacts were revised and pinned;
- `created`: missing artifacts were created and pinned;
- `no-change`: explicit finding that no evolution is needed, with pinned covering artifacts and a reason.

The pre-work gate blocks `/dr-do` when the disposition or immutable references are absent. Writing an evolution note after implementation does not clear the gate.

Review origin is derived from the authoritative source provider's immutable source-kind metadata (`customer_review`, `customer_brief`, `operator_amendment`, or another registered kind), not selected by the implementer. `customer_review` and amendments to prior delivered work always arm this gate.

`created` and `revised` route to a bounded pre-work evolution substage before authorization. Task-scoped reversible artifacts are changed and reviewed in that substage; framework-wide operating-model changes follow the existing Class B approval boundary. The task cannot enter `/dr-do` until the pinned artifact exists at the freeze commit. This is a real mutation stage, not a post-archive reflection note.

### 6. Evidence model

Every requirement needs load-bearing RED and GREEN events emitted by the framework evidence runner, not hand-authored metadata. They name a shared assertion ID, argv, exit code, observed repository SHA, hermeticity inputs, output digest, and retained evidence path. RED must be non-zero, GREEN zero, and both must name the same load-bearing assertion. The RED record also names the intentional mutation/negative control and the exact assertion that failed; setup, wrapper, or unrelated failures do not count. The runner signs or hashes a receipt over the command, repository tree, mutation diff, output, and result, and an independent quality review checks exact-head provenance. For migrated work, a present-day mutation or negative control may provide RED; historical RED is never invented. For customer-visible requirements the close gate additionally requires:

- exact merged and deployed SHA, with equality or an explicit build-provenance link;
- live HTTP and DOM evidence captured after deployment, including expected route identity and semantic assertions so an HTTP error or generic shell cannot pass;
- eight screenshot cells: RU and EN × mobile and desktop × light and dark;
- screenshot file digest, dimensions, viewport, theme, locale, URL, deployed SHA, DOM/content fingerprint, assertion result, and timestamp for every cell; cells cannot alias one retained file or one effective locale/theme/viewport state;
- customer disposition: `accepted`, `returned`, `deferred`, `rejected`, or `withdrawn`, with verbatim authority/source locator. Only customer-authenticated `withdrawn` removes a requirement from the coverage denominator; `deferred` remains incomplete.

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

Task delivery is complete only when all in-scope requirements pass and every in-scope requirement has customer-authenticated `accepted`, or has been removed from the denominator by customer-authenticated `withdrawn`. `returned` and `rejected` derive `rework_required`; `deferred` derives `blocked`. Epic delivery is complete only when its own requirements and every child from the independently resolved child manifest pass. Child references must be acyclic and resolve to the same monotonic project registry; cycles, missing children, or cross-project identity mismatches fail closed. A ledger-authored child list or stored `completed` status cannot override the provider manifest or a failing derived report. Suggested derived states are `not_started`, `in_progress`, `customer_review`, `rework_required`, `blocked`, and `complete`.

### 8. Lifecycle wiring

- `/dr-init`: classify the delivery lane; for armed lanes create the ledger and capture every initial verbatim remark as a distinct event.
- `/dr-prd`: atomize remarks, add typed production ACs/surface blueprints, and bind requirements to V-AC.
- `/dr-plan` and `/dr-design`: pin all capability and evolution references before implementation.
- `/dr-do`: run pre-work validation before source edits; require a committed freeze event before the first implementation commit; append implementation and RED/GREEN evidence after work.
- `/dr-qa`: verify implementation evidence and, for deployed work, the live matrix without accepting artifact-only completion.
- `/dr-compliance`: hard-enforce contract and coverage completeness for the task's declared delivery stage.
- `/dr-archive`: require derived complete state; unresolved customer-visible requirements block archive. An operator-authorized deferral may stop work at `blocked`, but it does not convert the requirement or epic to `complete`.
- `/dr-auto`: choose the next reversible action from exact missing requirement IDs, never from narrated epic status.
- `/dr-status`: render only derived coverage/state for armed tasks and epics.
- `/dr-quick`: classify first; customer-visible work either executes the same hard gates or routes into the full pipeline before any implementation.
- `/dr-write`, `/dr-edit`, and `/dr-publish`: classify customer/content scope, preserve source remarks, and never treat draft preparation or publication tooling as visitor-visible delivery. Actual publication remains operator-gated.
- `/dr-next` and `/dr-orchestrate`: replay and dispatch from the derived next missing gate without bypassing lane enforcement.

The shared command router requires classification before any task-creating or task-advancing command. The named command integrations are regression-tested, but the hard invariant is capability-based: a new entry point that can create, implement, review, close, publish, or archive work fails validation until it declares its customer-delivery behavior.

### 9. Project registration

The framework ships a project-registration template. Consumers register project ID, epic root, authoritative source and child-manifest providers, contract roots, public surface base URLs, surface blueprints, knowledge-reference resolver, deployment provenance probe, customer-authority policy, and a framework-release `canon_epoch`. The universal validator accepts adapters but keeps the core schema project-agnostic.

Adapters are data providers, never shell fragments or state authorities. Registration is accepted only from the project-governance location and authority pinned by the framework consumer registry. It uses argv arrays with an allowlisted executable, pinned executable digest/version, fixed project-relative working directory, explicit environment allowlist, timeout, stdout-size cap, and authenticated/schema-validated JSON results. The validator invokes without a shell, rejects path escapes and symlinks, and independently recomputes coverage. Adapters cannot emit derived state, acceptance, or passing assertions.

## Requirements

### D-REQ-01: Append-only atomic source mapping

Every authoritative source-manifest item is exhausted and has its own hash-chained capture event, stable source digest, and at least one atomic requirement ID; every requirement has at least one remark ID. Duplicate IDs, incomplete/paginated manifests, broken predecessor/event hashes, dangling mappings, empty verbatim text, source-digest mismatch, omitted source items, or history rewriting block all later phases.

### D-REQ-02: Visitor-visible AC or enabling parent

Every task classifies its delivery lane and every armed requirement declares exactly one class. A customer-visible requirement needs one atomic typed observable production outcome, target surface, and immutable blueprint. An enabling requirement needs a valid customer-visible parent from the authoritative manifest and cannot contribute delivered coverage to that parent. `none` is rejected when source intent names a customer or visitor outcome.

### D-REQ-03: Immutable pre-work capability bindings

Role, skill, blueprint, constraint, policy, and success criterion are all pinned with immutable revision and digest before implementation authorization. Any `Unbound`, `—`, mutable reference, missing class, absent freeze blob/authorization marker, target repository mismatch, dirty authorization base, or non-descendant implementation commit is a hard failure.

### D-REQ-04: Review-to-evolution

Customer-review requirements carry a pre-work evolution disposition and pinned artifacts. The pre-work gate goes RED when the disposition is absent or post-hoc and GREEN only when the requirement is covered before implementation.

### D-REQ-05: RED/GREEN evidence integrity

Each requirement carries distinct load-bearing RED and GREEN records. Evidence records include command/test identity, exit code, artifact digest, timestamp, and retained path. Identical/vacuous evidence, missing mutation assertion, or missing retained artifact blocks completion.

### D-REQ-06: Visitor-visible live delivery

A visitor-visible requirement is incomplete without exact deployment provenance, a semantic post-deploy live probe, all eight non-aliased screenshot cells, and customer-authenticated acceptance or withdrawal. Returned, rejected, or deferred work is not complete. Static or local artifacts cannot satisfy this requirement.

### D-REQ-07: Derived task and epic state

Coverage is computed from authoritative source and child manifests, mappings, requirements, evidence, and customer dispositions. The command emits machine-readable JSON and human-readable summaries with exact missing IDs. No ledger-authored denominator or stored completion field is accepted as authority.

### D-REQ-08: Phase-specific command gates

Every task-creating or task-advancing entry point classifies the lane and invokes the validator at the appropriate phase. The lifecycle, quick, content, replay, status, and orchestration commands named above fail closed on armed invalid contracts. Wiring tests discover command capabilities and reject any new bypass rather than merely grepping a fixed nine-command list.

### D-REQ-09: Compatibility and migration

New L1-L4 tasks classify their lane after the exact framework release/version/commit recorded as `canon_epoch`. Armed lanes are hard across all complexity levels. The consumer registry, outside the task ledger, records a monotonic adoption state that cannot revert from strict to legacy or `none`. Pre-epoch tasks are historical unless explicitly registered for strict adoption. A migration helper imports genuine source bytes as capture events, labels retroactive seeds as `legacy_unverified_source`, and imports existing implementation/tests/screenshots/deploy text only as `legacy_claim` events that do not satisfy coverage. It never invents remarks, bindings, RED/GREEN, live proof, or dispositions. Dual-read compatibility lasts exactly one release and has a named removal version.

### D-REQ-10: Security and evidence preservation

Verbatim external text is treated as data, never executed. CLI text inputs use files or JSON stdin, paths are root-confined, digests are recomputed, symlinks cannot escape the project root, and reports never print secrets. Evidence paths are durable and project-relative; `/tmp` cannot satisfy retention.

### D-REQ-11: Project registration and adapter boundary

The core validator remains project-agnostic. A registration schema defines exact contract roots, authoritative source/child manifests, surface matrices, constrained adapter argv, and customer authority. Missing, mutable, unsafe, non-executable, timed-out, oversized, or schema-invalid adapters fail only the phases that need them.

### D-REQ-12: Dogfood and independent reviews

TUNE-0585 has its own valid delivery ledger and authorization marker, captures runner-produced RED before implementation, passes focused and full suites, and receives a subordinate Codex exact-blob spec review before source work and exact-head quality review after implementation.

## Validation Acceptance Criteria

- **V-AC-1 — Atomic coverage:** provider-manifest omission/pagination, broken one-to-one, one-to-many, duplicate, dangling, and digest fixtures fail; valid exhausted mappings pass. Covers D-REQ-01 and D-REQ-02.
- **V-AC-2 — Pre-work gate:** one mutation per capability class plus `Unbound`, mutable ref, absent freeze/authorization marker, dirty or wrong base, and ancestry mutants fail; fully pinned fixture passes. Covers D-REQ-03.
- **V-AC-3 — Review evolution:** source-kind relabel, missing, unpinned, post-hoc, and created/revised-without-prework-mutation fixtures fail; reused/revised/created/no-change controls with pinned artifacts pass. Covers D-REQ-04.
- **V-AC-4 — Live close gate:** omitting each RED/GREEN, deploy, semantic-live, screenshot-cell, and disposition field fails independently; 404/generic-page, aliased-cell, forged-adapter, tool-only, returned, rejected, and deferred mutants remain RED. Covers D-REQ-05 and D-REQ-06.
- **V-AC-5 — Derived epic coverage:** omitted provider source/child, uncovered remark, uncovered child, child cycle, cross-project child, enabling-only child, and narrated-complete mutants fail with exact IDs; complete provider-backed acyclic graph passes. Covers D-REQ-07.
- **V-AC-6 — Command routing:** capability discovery proves all task-creating/advancing commands classify and gate armed work; L1, L2, quick, content, replay, and new-command mutants fail. Covers D-REQ-08.
- **V-AC-7 — Migration monotonicity:** exact `canon_epoch`, one-release dual read, strict-mode non-reversion, genuine-source import, and legacy-claim non-coverage fixtures pass independently. Covers D-REQ-09.
- **V-AC-8 — Runner and adapter safety:** argv/no-shell controls, executable/registration trust, timeout/output/env caps, path confinement, digest checks, authenticated result validation, and evidence-receipt provenance mutations pass. Covers D-REQ-05, D-REQ-10, and D-REQ-11.
- **V-AC-9 — Dogfood and review:** TUNE-0585's freeze and authorization commits predate implementation; focused/full exact-head validation, English-only surface, exact-blob spec-review disposition, and exact-head quality-review disposition are independently verified. Covers D-REQ-12.

## Error Handling

The validator uses stable exit codes: `0` phase satisfied, `1` contract/coverage finding, `2` usage or ledger-integrity failure, `3` adapter unavailable for a required phase. Findings include task ID, requirement ID, field/code, and remediation phase. Unknown schema versions, event types, enum values, broken hash chains, and escaped evidence paths fail closed.

## Rollout

1. Ship and release the universal framework mechanism through a protected PR.
2. Register TALO-0001 in an isolated Arcanada/Talomnia adoption task.
3. Import all customer remarks and canonical White Paper figures without inventing evidence.
4. Derive exact open requirement IDs.
5. Execute reversible Talomnia work requirement-by-requirement.
6. Deploy exact merged revisions, capture the live matrix, and record customer dispositions.

## Risks

- **False completeness through adapters:** constrained adapters provide data only; the core recomputes coverage and state against authoritative manifests.
- **Post-hoc timestamps:** same-repo ancestry and retained binding records are authoritative; timestamps alone never prove ordering.
- **Artifact explosion:** one task-level JSONL ledger and retained evidence directories keep the model bounded.
- **Legacy noise:** the pivot is default-strict for new tasks and opt-in strict for pre-pivot tasks.
- **Customer authority ambiguity:** registration names accepted authority kinds; agents cannot author `accepted` dispositions unless explicitly authorized.

## Downstream Boundary

This PRD is complete when the universal mechanism is released. It does not claim that Talomnia is delivered. TALO-0001 remains open until its imported requirement graph, sixteen canonical White Paper figures, product implementation, exact deployment, live screenshot matrix, and customer dispositions pass the new derived coverage gate.
