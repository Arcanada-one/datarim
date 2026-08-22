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

Normative event types are `lane_classified`, `source_manifest_bound`, `remark_captured`, `requirement_declared`, `production_ac_declared`, `atomicity_reviewed`, `parent_intent_bound`, `evolution_requested`, `evolution_approved`, `evolution_rejected`, `evolution_applied`, `evolution_reviewed`, `evolution_disposition`, `prework_contract_frozen`, `implementation_authorized`, `implementation_bound`, `red_observed`, `green_observed`, `production_deployment_observed`, `visual_observation`, `customer_disposition`, `enabling_disposition`, `child_manifest_bound`, and `event_superseded`.

Derived delivery state is never authored as an authoritative event. The validator calculates it from the current non-superseded event graph every run. Anchor receipts are external provider records, never in-ledger events, so anchoring cannot recurse. A locally valid chain is insufficient: every normal strict stage transition requires an authenticated receipt for the exact final event hash, event count, task ID, project ID, immutable Git blob OID, and content length. The provider acknowledges only after the complete blob is retrievable from its immutable/content-addressed store or protected Git ref; resolve re-downloads the bytes and recomputes both blob and event hashes. A shorter, divergent, missing, or unretrievable local/provider chain fails even when internal hashes are valid.

Canonical event bytes are precisely defined. JSON input rejects duplicate keys and accepts only strings, booleans, null, arrays/objects, and signed 64-bit integers; floats are forbidden. Strings are valid UTF-8 and retain their exact Unicode scalar sequence (no normalization). The hash preimage is the event object without `event_hash`, serialized as UTF-8 with keys sorted by Unicode code point, no insignificant whitespace, JSON lowercase literals, and minimal base-10 integers. String escaping is exact: quotation mark becomes `\"`; reverse solidus becomes `\\`; U+0008, U+000C, U+000A, U+000D, and U+0009 become `\b`, `\f`, `\n`, `\r`, and `\t`; every other U+0000-U+001F scalar becomes `\u00xx` with lowercase hexadecimal digits. U+2028 and U+2029 remain unescaped UTF-8. No solidus escaping, ASCII-only transformation, BOM, or trailing newline is permitted. `prev_event_hash` is inside the preimage. Shipped cross-runtime test vectors fix every boundary.

### 2. Atomic identity and source coverage

`remark_id` and `requirement_id` are immutable within a task. Every remark maps to at least one requirement. Every requirement maps back to at least one remark. Duplicate verbatim remarks may share a content digest but retain distinct source locators. A one-to-many decomposition is explicit. For an armed lane, a missing genuine source blocks: agent-authored Overview prose can be retained only as `legacy_unverified_source`, never as `verbatim` customer provenance.

The denominator is not the ledger's self-declared `remark_captured` set. `source_manifest_bound` pins an authoritative, provider-produced inventory of complete source containers and stable item identifiers: the init-task brief and append-log records for native tasks, plus the project registration's issue/comment/document adapters for imported work. The validator independently resolves every manifest item, recomputes its bytes and digest, and rejects uncaptured, multiply captured, missing, or extra source items. A source manifest is valid only when the adapter proves pagination/exhaustion and its exact manifest head is retained by the monotonic anchor authority. Semantic atomization is then independently reviewed: a single source item may produce several requirements, but it cannot disappear through aggregation.

Verbatim bytes are private data, not necessarily public Git data. Native tasks keep them in the gitignored init-task/private source store; imports may use a registered encrypted or access-controlled source vault. The public ledger records a pseudonymous item ID, byte length, versioned HMAC-SHA-256 commitment, source-kind, authority class, and an opaque locator—not the private text—unless the project explicitly classifies that text as publishable. The HMAC key remains in the private provider. For commitment profile `datarim-source-hmac-sha256-v1`, the HMAC preimage is the canonical-JSON byte serialization defined above of exactly this object and no other framing bytes: `{"byte_length":N,"item_id":"...","key_id":"...","profile":"datarim-source-hmac-sha256-v1","project_id":"...","schema_version":1,"source_b64":"...","task_id":"..."}`. `source_b64` is RFC 4648 standard-alphabet Base64 of the original source bytes, with required `=` padding and no whitespace or line wrapping; `N` is the original byte length. HMAC-SHA-256 is computed over those exact UTF-8 canonical bytes, and the public commitment is lowercase hexadecimal. This domain separation binds profile/schema/project/task/item/key ID and length without delimiter ambiguity. Rotation cross-signs old/new key metadata, retains the old key for historical verification, and never rewrites commitments. The source provider must return the original bytes for validation without logging them. Deletion or alteration fails the anchored commitment; public identifiers cannot expose provider-native issue/comment/user IDs. Reports redact content by default.

### 3. Delivery lanes and surface blueprints

- `customer-visible-v1`: requirements must carry a production route/surface and the complete live proof chain.
- `enabling-v1`: requirements may close on their own implementation evidence only when they name a customer-visible parent requirement in an authoritative manifest. They never mark the parent delivered.
- `none`: the task contains no customer-delivery requirement. It records a reason and cannot be used for a task whose init-task or append-log contains a customer remark or visitor-facing outcome.

Every task classifies its lane, so the canon is universal. The expensive production matrix is hard only where semantics require it, which permits private research, legal, documentation, API, CLI, framework, and tooling work to close honestly without allowing it to satisfy customer-facing work.

Customer-visible and enabling dispositions are deliberately different. Customer-visible completion requires customer-authenticated `accepted` or denominator-removing `withdrawn`. An enabling requirement may close only with a project-authority-signed `verified` disposition after its implementation/RED/GREEN chain passes. It contributes zero customer-delivery coverage to its parent. `parent_intent_bound` may bind a pre-registration parent from an authenticated operator/customer source record; later project registration must resolve to the same project/task/requirement identity or the enabling task reopens.

Each customer-visible requirement names a pinned surface blueprint with typed executable predicates. `bilingual-web-v1` requires the exact RU/EN × mobile/desktop × light/dark eight-cell matrix and may be widened but not narrowed by registration. Other shipped blueprints define equivalent visitor-observation dimensions for native, CLI, API, and published-document surfaces; none permits tools, source documents, tests, or local-only output to substitute for the actual customer-consumed production surface. Talomnia uses `bilingual-web-v1`.

Atomicity is structural and independently reviewed: one requirement has one subject, one observable behavior, one terminal disposition, and one surface blueprint; its production AC is a typed predicate plus expected value, not prose alone. A source item that contains conjunctions, multiple routes, or independently rejectable outcomes must decompose. `atomicity_reviewed` binds the authoritative source-manifest digest, exact ordered digest of all active requirement and production-AC events, complete remark-to-requirement cardinality, reviewer identity/trust proof, exact predecessor ledger head/spec revision, and verdict. Any later declaration, amendment, or supersession of a source/requirement/AC invalidates the review and downstream freeze. A passing review receipt is required before freeze; aggregate catch-all requirements fail review and validation.

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

`/dr-plan` owns and invokes a bounded pre-work evolution substage before authorization. Owner mapping is registry-derived, not implementer-selected: blueprint/policy/constraint/success-criterion → `architect`; skill/role → `skill-creator`; a project may narrow authority but never grant the implementer approval authority. The durable state machine has two non-conflated branches. Approval follows `evolution_requested → blocked` (when approval is required) → `evolution_approved → evolution_applied → evolution_reviewed → evolution_disposition → prework_contract_frozen`. Rejection follows `evolution_requested → blocked → evolution_rejected` and remains blocked; it may terminate only as an authenticated declined disposition or begin a new request with a new request ID, and it can never transition to `evolution_applied`. Every event binds request ID, prior ledger head, exact artifact before/after digest, owner trust proof, approval record where required, and resume cursor. A crash resumes at the first missing valid transition, never against an unapproved/newer artifact. Task-scoped reversible artifacts are changed and reviewed in the approved substage, then control returns to `/dr-plan` for refreeze. Framework-wide operating-model changes follow the existing Class B approval boundary. The task cannot enter `/dr-do` until the pinned artifact exists at the freeze commit.

### 6. Evidence model

Every requirement needs load-bearing RED and GREEN events emitted by the framework evidence runner, not hand-authored metadata. They name a shared assertion ID, argv, exit code, observed repository SHA, hermeticity inputs, output digest, and retained evidence path. RED must be non-zero, GREEN zero, and both must name the same load-bearing assertion. The RED record also names the intentional mutation/negative control and the exact assertion that failed; setup, wrapper, or unrelated failures do not count. The runner produces a signed attestation over the command, repository tree, mutation diff, output, and result using a trust root pinned in the consumer registry (`git-ssh-v1`, `sigstore-oidc-v1`, or another shipped verifier profile); an unauthenticated digest alone never proves execution. An independent quality review checks exact-head provenance. For migrated work, a present-day mutation or negative control may provide RED; historical RED is never invented. For customer-visible requirements the close gate additionally requires:

- exact merged and deployed SHA, with equality or an explicit build-provenance link;
- live HTTP and DOM evidence captured after deployment, including expected route identity and semantic assertions so an HTTP error or generic shell cannot pass;
- eight screenshot cells: RU and EN × mobile and desktop × light and dark;
- screenshot file digest, dimensions, viewport, theme, locale, URL, deployed SHA, DOM/content fingerprint, assertion result, and timestamp for every cell; cells cannot alias one retained file or one effective locale/theme/viewport state;
- customer disposition: `accepted`, `returned`, `deferred`, `rejected`, or `withdrawn`, resolved from an authenticated customer-authority record with stable record ID, signer/identity proof, verbatim private-source locator/digest, timestamp, and exact requirement/deployed-SHA binding. The event is only a reference; the validator refetches and verifies the registered authority record. Only customer-authenticated `withdrawn` removes a requirement from the coverage denominator; `deferred` remains incomplete.

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

Customer-visible task delivery is complete only when all in-scope requirements pass and every in-scope requirement has customer-authenticated `accepted`, or has been removed from the denominator by customer-authenticated `withdrawn`. `returned` and `rejected` derive `rework_required`; `deferred` derives `blocked`. Enabling task delivery is complete only when every enabling requirement passes implementation/RED/GREEN and carries project-authority `verified`; that state never changes the parent denominator. Epic delivery is complete only when its own customer-visible requirements and every child from the independently resolved child manifest pass. Child references must be acyclic and resolve to the same monotonic project registry; cycles, missing children, or cross-project identity mismatches fail closed. A ledger-authored child list or stored `completed` status cannot override the provider manifest or a failing derived report. Suggested derived states are `not_started`, `in_progress`, `customer_review`, `rework_required`, `blocked`, and `complete`.

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

The consumer registry itself is signed by the framework/project governance trust root and pins profile version, verifier executable digest, algorithm, key/issuer, subject, audience, role scopes, repository/project/requirement scopes, validity interval, and revocation-list digest. Rotation requires an old-and-new cross-signature or an explicit operator recovery record; revoked/expired keys invalidate new receipts but historical receipts retain validation against the signed historical registry. Profile downgrade is forbidden after `canon_epoch`. Evidence/reviewer/project/customer roles are disjoint: a valid developer or runner key cannot sign atomicity review, enabling verification, or customer disposition.

The first shipped provider profiles are concrete:

- `git-protected-ref-v1` is the ongoing monotonic head authority. It requires a dedicated remote branch whose host rules forbid deletion and non-fast-forward updates while permitting append-only fast-forwards, verifies those rules through a pinned host API profile, and anchors a ledger head only when the exact ledger blob and receipt commit are reachable from that protected ref. Each strict stage transition is merged through the protected review path before the next stage. Git credentials come from the existing credential helper; tokens are never command arguments.
- `git-immutable-tag-v1` is the one-shot genesis/release anchor. It requires a tag namespace whose host rules forbid deletion, non-fast-forward, and update; the canon's reviewed release tag anchors the final genesis ledger but cannot serve subsequent append transitions.
- `git-ssh-v1` authenticates runner/reviewer receipts with `ssh-keygen -Y sign/verify`, a fixed namespace per receipt class, and a project-registry allowed-signers file pinned by digest and scoped as above. Private keys stay in the configured agent/CI signer; the registry stores public identities only.
- source, customer, and child providers use the same constrained adapter envelope and an authenticated provider-specific receipt. A project without a passing trust/authority probe cannot arm strict mode.

The plan must perform a ≤60-second feasibility probe of executable availability, signer verification, remote rules, credential scope, and an append/resolve dry run before implementation. Documentation is not proof of provider behavior.

Adapters are data providers, never shell fragments or state authorities. Registration is accepted only from the project-governance location and authority pinned by the framework consumer registry. It uses argv arrays with an allowlisted executable, pinned executable digest/version, fixed project-relative working directory, explicit environment allowlist, timeout, stdout-size cap, and authenticated/schema-validated JSON results. The validator invokes without a shell, rejects path escapes and symlinks, and independently recomputes coverage. Adapters cannot emit derived state or passing assertions. A customer-authority adapter may resolve an existing signed acceptance record but cannot create one; the core verifies its trust proof. The separate head-anchor adapter exposes append/resolve operations backed by a monotonic provider and rejects rollback or divergent heads.

### 10. Writer durability and authority transitions

The writer serializes per-task appends with an advisory lock that carries owner/process/start metadata and a bounded stale-lock recovery rule. It validates the current anchored head, writes and fsyncs a complete temporary file, atomically renames, fsyncs the containing directory, publishes the complete immutable blob, then requests a compare-and-append head receipt. Duplicate retries are idempotent by event ID and payload digest. Concurrent/divergent predecessors fail without overwriting either branch. Disk-full, short write, signal/process death, publication/anchor timeout, and failure between rename/publication/anchor leave an explicit recoverable `unanchored` state; no stage gate passes until reconciliation proves the exact published blob and anchors it.

Supersession is deterministic. Source captures, identity/manifest bindings, atomicity reviews, authorization, evidence observations, dispositions, and external anchor receipts are never semantically removed. Source/requirement/AC/prework declarations may be amended only before authorization by the scoped governance signer; doing so invalidates atomicity review/freeze and all downstream events. Implementation/evidence/deploy/visual observations are countermanded only by a newer valid observation with the same typed identity and scoped runner/provider signer; the highest event sequence on one anchored chain wins. Customer disposition is resolved by the customer provider's monotonic record sequence, never ledger order, and any returned/rejected record reopens. Two events with the same predecessor are a divergence and neither wins until an authority-signed reconciliation event names both hashes and the chosen successor. `event_superseded` carries target ID/type, replacement ID, reason, signer scope, and invalidation set; any other target/actor pair fails closed.

### 11. Genesis bootstrap

A framework cannot use an unimplemented runner/anchor to prove its own creation. The sole bootstrap is explicit and non-passing:

1. A reviewed PRD/plan commit exists first.
2. A separate genesis-freeze commit records the private-source digests, atomic requirement mapping/review, all existing pinned capabilities, target base, and selected provider profiles. It may not pin a skill or tool that does not yet exist.
3. A separate authorization commit descends from the freeze and records the clean target base. Ordinary repository TDD then drives the initial implementation; those raw Bats outputs are development evidence, not canonical runner attestations.
4. Once the runner exists, a present-day controlled mutation produces canonical signed RED, the restored exact head produces signed GREEN, and the full branch receives independent exact-head review.
5. The bootstrap remains `genesis_unanchored` and cannot report canonical completion until the exact ledger/receipt head is merged and its reviewed release tag passes `git-immutable-tag-v1`. That immutable tag becomes the `canon_epoch`; all later tasks use the normal strict sequence with a configured `git-protected-ref-v1` branch.

This exception applies only to the implementation of the canon's own missing enforcement machinery. It never converts historical output into pre-implementation RED and never applies to Talomnia or later consumers.

## Requirements

#### D-REQ-01: Append-only atomic source mapping

Every authoritative source-manifest item is exhausted and has its own hash-chained capture event, stable source digest, and at least one atomic requirement ID; every requirement has at least one remark ID. Duplicate IDs, incomplete/paginated manifests, broken predecessor/event hashes, dangling mappings, empty verbatim text, source-digest mismatch, omitted source items, or history rewriting block all later phases.

#### D-REQ-02: Visitor-visible AC or enabling parent

Every task classifies its delivery lane and every armed requirement declares exactly one class. A customer-visible requirement needs one atomic typed observable production outcome, target surface, and immutable blueprint. An enabling requirement needs a valid customer-visible parent from the authoritative manifest and cannot contribute delivered coverage to that parent. `none` is rejected when source intent names a customer or visitor outcome.

#### D-REQ-03: Immutable pre-work capability bindings

Role, skill, blueprint, constraint, policy, and success criterion are all pinned with immutable revision and digest before implementation authorization. Any `Unbound`, `—`, mutable reference, missing class, absent freeze blob/authorization marker, target repository mismatch, dirty authorization base, or non-descendant implementation commit is a hard failure.

#### D-REQ-04: Review-to-evolution

Customer-review requirements carry a pre-work evolution disposition and pinned artifacts. The pre-work gate goes RED when the disposition is absent or post-hoc and GREEN only when the requirement is covered before implementation. An approved request alone may apply changes; a rejected request remains blocked, cannot apply or freeze, and may resume only through an authenticated terminal decline or a distinct new request ID.

#### D-REQ-05: RED/GREEN evidence integrity

Each requirement carries distinct load-bearing RED and GREEN records. Evidence records include command/test identity, exit code, artifact digest, timestamp, and retained path. Identical/vacuous evidence, missing mutation assertion, or missing retained artifact blocks completion.

#### D-REQ-06: Visitor-visible live delivery

A visitor-visible requirement is incomplete without exact deployment provenance, a semantic post-deploy live probe, all eight non-aliased screenshot cells, and customer-authenticated acceptance or withdrawal. Returned, rejected, or deferred work is not complete. Static or local artifacts cannot satisfy this requirement.

#### D-REQ-07: Derived task and epic state

Coverage is computed from authoritative source and child manifests, mappings, requirements, evidence, and customer dispositions. The command emits machine-readable JSON and human-readable summaries with exact missing IDs. No ledger-authored denominator or stored completion field is accepted as authority.

#### D-REQ-08: Phase-specific command gates

Every task-creating or task-advancing entry point classifies the lane and invokes the validator at the appropriate phase. The lifecycle, quick, content, replay, status, and orchestration commands named above fail closed on armed invalid contracts. Wiring tests discover command capabilities and reject any new bypass rather than merely grepping a fixed nine-command list.

#### D-REQ-09: Compatibility and migration

New L1-L4 tasks classify their lane after the exact framework release/version/commit recorded as `canon_epoch`. Armed lanes are hard across all complexity levels. The consumer registry, outside the task ledger, records a monotonic adoption state that cannot revert from strict to legacy or `none`. Pre-epoch tasks are historical unless explicitly registered for strict adoption. A migration helper imports genuine source bytes as capture events, labels retroactive seeds as `legacy_unverified_source`, and imports existing implementation/tests/screenshots/deploy text only as `legacy_claim` events that do not satisfy coverage. It never invents remarks, bindings, RED/GREEN, live proof, or dispositions. Dual-read compatibility lasts exactly one release and has a named removal version.

#### D-REQ-10: Security and evidence preservation

Verbatim external text is treated as data, never executed. CLI text inputs use files or JSON stdin, paths are root-confined, commitments are recomputed through the private provider, symlinks cannot escape the project root, and reports never print secrets or provider-native identifiers. Evidence paths are durable and project-relative; `/tmp` cannot satisfy retention.

#### D-REQ-11: Project registration and adapter boundary

The core validator remains project-agnostic. A governance-signed registration schema defines exact contract roots, authoritative source/child manifests, surface matrices, constrained adapter argv, disjoint signer roles/scopes, verifier revisions, revocation/rotation policy, and customer authority. Missing, mutable, unsafe, downgraded, unauthorized, revoked, non-executable, timed-out, oversized, or schema-invalid adapters/receipts fail only the phases that need them.

#### D-REQ-12: Honest genesis and independent reviews

TUNE-0585 follows the two-commit genesis freeze/authorization sequence before implementation, labels raw TDD as development-only, captures a present-day signed mutation RED and restored GREEN after the runner exists, passes focused/full suites, and receives subordinate exact-blob spec review before source work and exact-head quality review after implementation. It cannot claim canonical completion until the resulting head is merged and anchored on the selected protected ref.

#### D-REQ-13: Privacy-safe monotonic authority and durable writes

Private verbatim bytes remain in an access-controlled source provider while public ledger records retain pseudonymous HMAC commitments. Every accepted ledger head is externally anchored to a retrievable immutable ledger blob. Canonical bytes are runtime-independent. Concurrent writers, retries, stale locks, crash points, disk-full, divergent heads, truncation, rollback, key rotation/revocation, and unauthorized/ambiguous supersession have deterministic fail-closed or recoverable behavior without losing acknowledged events.

## Validation Acceptance Criteria

### V-AC-1 — Atomic coverage

Provider-manifest omission/pagination, private-source deletion/alteration, public identifier leakage, HMAC key/domain/rotation mismatch, broken one-to-one, one-to-many, aggregate catch-all, missing/stale atomicity review, duplicate, dangling, and commitment fixtures fail; valid exhausted mappings with an exact-graph authenticated atomicity review pass.
Covers: D-REQ-01, D-REQ-02

### V-AC-2 — Pre-work gate

One mutation per capability class plus `Unbound`, mutable ref, absent freeze/authorization marker, dirty or wrong base, and ancestry mutants fail; a fully pinned fixture passes.
Covers: D-REQ-03

### V-AC-3 — Review evolution

Source-kind relabel, missing, unpinned, post-hoc, created/revised-without-prework-mutation, rejected-to-applied, rejected-to-freeze, reused-rejected-request-ID, unauthenticated-decline, and crash-resume-after-rejection fixtures fail independently; reused/revised/created/no-change controls with pinned artifacts and a new-ID retry after rejection pass.
Covers: D-REQ-04

### V-AC-4 — Live close gate

Omitting each RED/GREEN, deploy, semantic-live, screenshot-cell, and disposition field fails independently; 404/generic-page, aliased-cell, forged-adapter, tool-only, returned, rejected, and deferred mutants remain RED.
Covers: D-REQ-06

### V-AC-5 — Derived epic coverage

Omitted provider source/child, uncovered remark, uncovered child, child cycle, cross-project child, enabling-only child, and narrated-complete mutants fail with exact IDs; a complete provider-backed acyclic graph passes.
Covers: D-REQ-07

### V-AC-6 — Command routing

Capability discovery proves all task-creating/advancing commands classify and gate armed work; L1, L2, quick, content, replay, and new-command mutants fail.
Covers: D-REQ-08

### V-AC-7 — Migration monotonicity

Exact `canon_epoch`, one-release dual read, strict-mode non-reversion, genuine-source import, and legacy-claim non-coverage fixtures pass independently.
Covers: D-REQ-09

### V-AC-8 — Runner and adapter safety

Argv/no-shell controls, executable/registration trust, timeout/output/env caps, path confinement, commitment checks, forged/hash-only runner receipts, wrong-role/scope/audience/namespace, expired/revoked/downgraded profiles, forged customer dispositions, authenticated result validation, and evidence-receipt provenance mutations pass.
Covers: D-REQ-05, D-REQ-10, D-REQ-11

### V-AC-9 — Genesis and review

TUNE-0585's reviewed spec, genesis freeze, and authorization are three ordered commits before implementation; raw TDD is not canonical evidence; present-day signed mutation RED/restored GREEN, focused/full exact-head validation, English-only surface, exact-blob spec-review disposition, protected-ref anchor, and exact-head quality-review disposition are independently verified.
Covers: D-REQ-12

### V-AC-10 — Monotonic durability and privacy

Private-source redaction, cross-runtime canonical-byte vectors, missing immutable blob, anchored-head truncation/rollback/divergence, anchor self-reference absence, target/actor/conflict supersession, concurrent append, duplicate retry, stale lock, disk-full/short-write, process-death-before/after rename/publication, directory-fsync, anchor-timeout-after-accept, and unanchored recovery fixtures each preserve acknowledged bytes/history and fail closed until reconciled.
Covers: D-REQ-13

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

- **False completeness through adapters:** constrained authenticated adapters provide data only; the core recomputes coverage and state against authoritative manifests and pinned trust roots.
- **Post-hoc timestamps:** same-repo ancestry and retained binding records are authoritative; timestamps alone never prove ordering.
- **Local rollback:** hash chaining alone is insufficient, so no stage transition trusts an unanchored local head.
- **Privacy leak:** public ledgers retain salted digests and opaque locators by default; verbatim bytes remain in the registered private source provider.
- **Artifact explosion:** one task-level JSONL ledger and retained evidence directories keep the model bounded.
- **Legacy noise:** the pivot is default-strict for new tasks and opt-in strict for pre-pivot tasks.
- **Customer authority ambiguity:** registration names accepted authority kinds; agents cannot author `accepted` dispositions unless explicitly authorized.

## Downstream Boundary

This PRD is complete when the universal mechanism is released. It does not claim that Talomnia is delivered. TALO-0001 remains open until its imported requirement graph, sixteen canonical White Paper figures, product implementation, exact deployment, live screenshot matrix, and customer dispositions pass the new derived coverage gate.
