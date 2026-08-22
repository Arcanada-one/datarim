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

Normative event types are `lane_classified`, `source_manifest_bound`, `remark_captured`, `requirement_declared`, `production_ac_declared`, `atomicity_reviewed`, `parent_intent_bound`, `evolution_requested`, `evolution_blocked`, `evolution_approved`, `evolution_rejected`, `evolution_declined`, `evolution_applied`, `evolution_reviewed`, `evolution_disposition`, `prework_contract_frozen`, `implementation_authorized`, `implementation_bound`, `red_observed`, `green_observed`, `production_deployment_observed`, `visual_observation`, `customer_disposition`, `enabling_disposition`, `child_manifest_bound`, `legacy_claim_imported`, `head_reconciled`, and `event_superseded`.

Derived delivery state is never authored as an authoritative event. The validator calculates it from the current non-superseded event graph every run. Anchor receipts are external provider records, never in-ledger events, so anchoring cannot recurse. A locally valid chain is insufficient: every normal strict stage transition requires an authenticated receipt for the exact final event hash, event count, task ID, project ID, immutable Git blob OID, and content length. The provider acknowledges only after the complete blob is retrievable from its immutable/content-addressed store or protected Git ref; resolve re-downloads the bytes and recomputes both blob and event hashes. A shorter, divergent, missing, or unretrievable local/provider chain fails even when internal hashes are valid.

Canonical event bytes are precisely defined. JSON input rejects duplicate keys and accepts only strings, booleans, null, arrays/objects, and signed 64-bit integers; floats are forbidden. Strings are valid UTF-8 and retain their exact Unicode scalar sequence (no normalization). The hash preimage is the event object without `event_hash`, serialized as UTF-8 with keys sorted by Unicode code point, no insignificant whitespace, JSON lowercase literals, and minimal base-10 integers. String escaping is exact: quotation mark becomes `\"`; reverse solidus becomes `\\`; U+0008, U+000C, U+000A, U+000D, and U+0009 become `\b`, `\f`, `\n`, `\r`, and `\t`; every other U+0000-U+001F scalar becomes `\u00xx` with lowercase hexadecimal digits. U+2028 and U+2029 remain unescaped UTF-8. No solidus escaping, ASCII-only transformation, BOM, or trailing newline is permitted. `prev_event_hash` is inside the preimage. Shipped cross-runtime test vectors fix every boundary.

Schema v1 fixes the full event envelope. Every line has exactly `schema_version` (integer `1`), `event_index`, `event_id`, `event_type`, `project_id`, `task_id`, `recorded_at`, `payload`, `prev_event_hash`, and `event_hash`; unknown or missing keys fail. `event_index` is the zero-based signed 64-bit non-negative physical line index. IDs are non-empty ASCII strings matching `^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$`. `recorded_at` is UTC `YYYY-MM-DDTHH:MM:SSZ` with no fraction. The genesis predecessor is exactly 64 lowercase zeroes. Every later predecessor equals the prior line's `event_hash`. `event_hash` is the 64-character lowercase hexadecimal SHA-256 of the canonical preimage. The stored line is the canonical full event including `event_hash` followed by exactly one LF; LF is not hashed, blank lines and a missing final LF fail. Arrays retain declared order; set-like arrays identified below must already be ascending by canonical byte value with no duplicates.

Schema v1 fixes primitive and reusable payload types. `id128` is an ASCII string matching `^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$`; `sha256` is exactly 64 lowercase hexadecimal characters; `git_oid` is exactly 40 lowercase hexadecimal characters; `utc_seconds` matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` and must be a real UTC date; `text` is 1–4096 Unicode scalars with no U+0000; `relative_path` is 1–1024 UTF-8 bytes, uses `/`, is not absolute, and has no empty, `.`, `..`, or symlink-resolved escaping segment; `locator` is either a `relative_path` or a 1–2048-byte registered URI with no control scalar; `https_url` is an absolute HTTPS URL with no credentials or fragment. Integers are signed 64-bit; counts, indexes, dimensions, byte lengths, registry/provider sequences, and resume cursors are non-negative. No payload value is null unless explicitly allowed below.

`authority` has exactly `registry_revision:uint`, `role:authority_role`, `key_id:id128`, and `namespace:id128`. It does not contain the event signature: the configured receipt provider resolves a detached `event-attestation` by `(project_id, task_id, event_id, event_hash)`, preventing signature self-reference, and the validator verifies it before accepting the event. `artifact_ref` has exactly `id:id128`, `revision:text`, `sha256:sha256`, `locator:locator`, and `binding_commit:git_oid`. `receipt_ref` has exactly `profile:id128`, `locator:locator`, `sha256:sha256`, `signer_key_id:id128`, and `namespace:id128`; it refers to an independently existing provider record, never a signature over the event containing the reference. `conflict_ref` has exactly `event_id:id128` and `head_hash:sha256`. `typed_predicate` has exactly `kind`, `selector`, `operator`, and `expected`; `kind` is one of `dom`, `http`, `image`, `cli`, `api`, or `document`; `selector` is `text`; `operator` is one of `equals`, `contains`, `matches`, `exists`, `not_exists`, `http_status`, `image_digest`, or `dom_fingerprint`; `expected` is a string, boolean, null, signed 64-bit integer, or an ordered array of those scalars. Every payload contains non-null `authority` plus exactly the following type-specific keys; every `[]` value is a duplicate-free ascending array by canonical bytes unless explicitly described as ordered:

For event index `n`, the `event-attestation` subject's `ledger_preimage_sha256` is SHA-256 of the exact stored ledger-prefix bytes for physical lines `[0,n)`, including every prior line's terminating LF; for genesis it is SHA-256 of the empty byte string. It is distinct from `event_hash`, which hashes the current canonical event preimage.

| Event type | Exact type-specific payload keys |
|---|---|
| `lane_classified` | `lane`, `reason`, `source_receipt` |
| `source_manifest_bound` | `provider_id`, `manifest_id`, `manifest_sha256`, `manifest_anchor`, `item_count`, `exhausted` |
| `remark_captured` | `remark_id`, `manifest_item_id`, `pseudonymous_item_id`, `byte_length`, `commitment_profile`, `key_id`, `commitment`, `source_kind`, `authority_class`, `opaque_locator` |
| `requirement_declared` | `requirement_id`, `remark_ids[]`, `requirement_class`, `title` |
| `production_ac_declared` | `requirement_id`, `ac_id`, `blueprint_ref`, `surface_id`, `predicate` |
| `atomicity_reviewed` | `source_manifest_sha256`, `requirement_graph_sha256`, `mapping_cardinality`, `reviewer_receipt`, `predecessor_head`, `spec_revision`, `verdict` |
| `parent_intent_bound` | `parent_project_id`, `parent_task_id`, `parent_requirement_id`, `source_receipt` |
| `evolution_requested` | `request_id`, `replaces_request_id`, `artifact_class`, `artifact_before`, `proposed_action`, `owner_role`, `resume_cursor` |
| `evolution_blocked` | `request_id`, `reason_code`, `approval_required`, `resume_cursor` |
| `evolution_approved` | `request_id`, `approval_receipt`, `resume_cursor` |
| `evolution_rejected` | `request_id`, `rejection_receipt`, `reason`, `resume_cursor` |
| `evolution_declined` | `request_id`, `decline_receipt`, `terminal`, `resume_cursor` |
| `evolution_applied` | `request_id`, `artifact_before`, `artifact_after`, `resume_cursor` |
| `evolution_reviewed` | `request_id`, `artifact_after`, `reviewer_receipt`, `verdict`, `resume_cursor` |
| `evolution_disposition` | `request_id`, `disposition`, `covering_artifacts[]`, `reason`, `resume_cursor` |
| `prework_contract_frozen` | `contract_base_commit`, `contract_manifest_sha256`, `requirement_graph_sha256`, `role_refs[]`, `skill_refs[]`, `blueprint_refs[]`, `constraint_refs[]`, `policy_refs[]`, `success_criterion_refs[]` |
| `implementation_authorized` | `repository_id`, `clean_base_sha`, `freeze_commit`, `marker_commit`, `marker_path`, `marker_sha256`, `dirty_inventory_sha256`, `authorization_receipt` |
| `implementation_bound` | `repository_id`, `authorization_event_id`, `first_implementation_commit`, `implementation_tree_sha256` |
| `red_observed` | `requirement_id`, `assertion_id`, `argv[]` (ordered), `exit_code`, `repository_sha`, `hermeticity_sha256`, `output_sha256`, `evidence_path`, `mutation_id`, `mutation_diff_sha256`, `failed_assertion`, `runner_receipt` |
| `green_observed` | `requirement_id`, `assertion_id`, `argv[]` (ordered), `exit_code`, `repository_sha`, `hermeticity_sha256`, `output_sha256`, `evidence_path`, `restored_tree_sha256`, `runner_receipt` |
| `production_deployment_observed` | `requirement_id`, `source_sha`, `deployed_sha`, `build_provenance`, `deployment_receipt` |
| `visual_observation` | `requirement_id`, `locale`, `viewport`, `theme`, `screenshot_path`, `screenshot_sha256`, `width`, `height`, `url`, `deployed_sha`, `dom_fingerprint`, `assertion_result`, `observed_at`, `provider_receipt` |
| `customer_disposition` | `requirement_id`, `deployed_sha`, `disposition`, `customer_record` |
| `enabling_disposition` | `requirement_id`, `disposition`, `project_receipt` |
| `child_manifest_bound` | `provider_id`, `manifest_id`, `manifest_sha256`, `manifest_anchor`, `child_count`, `exhausted` |
| `legacy_claim_imported` | `claim_id`, `claim_kind`, `source_locator`, `source_sha256`, `reason_non_authoritative` |
| `head_reconciled` | `conflicts[]`, `chosen_successor_event_id`, `reconciliation_receipt` |
| `event_superseded` | `target_event_id`, `target_event_type`, `replacement_event_id`, `reason`, `signer_scope`, `invalidation_set[]` |

The shipped `config/customer-delivery-event-v1.schema.json` is an exact executable transcription; it cannot invent additional restrictions. Field types are closed as follows:

- all names ending `_id` or `_profile` and the fields `lane`, `profile`, `key_id`, `source_kind`, `authority_class`, `requirement_class`, `artifact_class`, `proposed_action`, `owner_role`, `reason_code`, `verdict`, `disposition`, `claim_kind`, `locale`, `viewport`, `theme`, `signer_scope`, and `repository_id` are `id128` enums or IDs as enumerated below; `replaces_request_id` is `id128|null`;
- `event_type` and `target_event_type` are members of the normative event enum;
- every field ending `_sha256`, plus `commitment`, `predecessor_head`, and `head_hash`, is `sha256`;
- `contract_base_commit`, `clean_base_sha`, `freeze_commit`, `marker_commit`, `first_implementation_commit`, `repository_sha`, `source_sha`, `deployed_sha`, and `spec_revision` are `git_oid`;
- fields ending `_path` are `relative_path`; `opaque_locator`, `source_locator`, and every nested `locator` are `locator`; `url` is `https_url`; `recorded_at` and `observed_at` are `utc_seconds`;
- `reason`, `title`, `failed_assertion`, and `reason_non_authoritative` are `text`; `item_count`, `child_count`, `byte_length`, `width`, `height`, `exit_code`, and `resume_cursor` are bounded integers; `exhausted`, `approval_required`, `terminal`, and `assertion_result` are booleans, and `terminal` must be true;
- `mapping_cardinality` has exactly `remark_count:uint`, `requirement_count:uint`, and `edge_count:uint`; `predicate` is a `typed_predicate`; `artifact_before`, `artifact_after`, and `blueprint_ref` are `artifact_ref`, with only `artifact_before` nullable and only for `proposed_action=create`;
- all fields ending `_receipt`, `_record`, or `_anchor`, plus `source_receipt`, `build_provenance`, and `customer_record`, are `receipt_ref`;
- `remark_ids` and `invalidation_set` contain `id128`; role/skill/blueprint/constraint/policy/success-criterion refs and `covering_artifacts` contain `artifact_ref`; `argv` is an ordered array of 0–65535-byte UTF-8 strings without U+0000; `conflicts` contains at least two `conflict_ref` records.

Enumerations are exact. `authority_role` is one of `governance`, `spec-reviewer`, `atomicity-reviewer`, `evolution-owner`, `evolution-reviewer`, `quality-reviewer`, `evidence-runner`, `project-verifier`, `customer-authority`, `source-provider`, `deployment-provider`, `visual-provider`, `release-authority`, `anchor-authority`, or `reconciliation-authority`. Lanes are `customer-visible-v1`, `enabling-v1`, or `none`; requirement classes are the first two. Source kinds are `customer_review`, `customer_brief`, `operator_amendment`, `customer_document`, or `legacy_unverified_source`; authority classes are `customer`, `operator`, `project`, or `legacy-unverified`.

Artifact classes are `role`, `skill`, `blueprint`, `constraint`, `policy`, or `success-criterion`; owner roles are `architect` or `skill-creator`; proposed actions are `create`, `revise`, `reuse`, or `no-change`; reason codes are `approval_required`, `changes_required`, `provider_unavailable`, or `authority_rejected`; review verdicts are `pass` or `fail`; evolution dispositions are `reused`, `revised`, `created`, or `no-change`; customer dispositions are `accepted`, `returned`, `deferred`, `rejected`, or `withdrawn`; enabling disposition is only `verified`; legacy claim kinds are `implementation`, `test`, `screenshot`, or `deployment`; locales are `ru` or `en`, viewports `mobile` or `desktop`, and themes `light` or `dark` for `bilingual-web-v1` (other versioned blueprints require a new enum-bearing schema version). `head_reconciled.conflicts` must pair every divergent event with its head, the pairs must share one predecessor, and `chosen_successor_event_id` must equal exactly one paired event ID. Any future payload field, enum value, or event type requires a new schema version and migration, never permissive schema-v1 parsing.

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

Before implementation starts, every armed requirement must pin exactly one or more immutable references for each class: role, skill, blueprint, constraint, policy, and success criterion. Each reference carries a logical ID, immutable revision, content digest, binding record locator, and binding commit. To avoid a Git fixed point, `prework_contract_frozen` names the already-existing `contract_base_commit` plus a canonical manifest digest of all bindings; it never claims the commit that contains itself. The validator derives `freeze_commit` as the first descendant whose tree contains the exact ledger blob/freeze event and verifies that commit independently. `implementation_authorized` then names that known freeze commit, the exact clean implementation-repository base SHA, a previously committed authorization-marker commit/path/digest, and an external authorization receipt. It never names the commit containing itself. The validator derives the authorization-event commit from Git, and implementation begins only after that commit exists. In a same-repository task, the first implementation commit descends from the authorization-event commit; across repositories, it descends from the named marker commit and the external receipt/provider sequence proves authorization-event publication preceded work. The validator rejects:

- literal or semantic `Unbound`;
- mutable revisions such as `main`, `master`, `latest`, branch-only URLs, or unversioned paths;
- any missing capability class;
- a contract base/freeze commit that does not predate the implementation authorization;
- a freeze event absent from the uniquely derived freeze commit or mismatching its contract manifest;
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

`/dr-plan` owns and invokes a bounded pre-work evolution substage before authorization. Owner mapping is registry-derived, not implementer-selected: blueprint/policy/constraint/success-criterion → `architect`; skill/role → `skill-creator`; a project may narrow authority but never grant the implementer approval authority. Each request's `resume_cursor` starts at 0 and increments by exactly one on every event carrying that request ID; a duplicate cursor with identical event digest is an idempotent replay, while a gap, regression, or different event at the same cursor is integrity failure.

The transition table is closed. `reuse` and `no-change` emit only `evolution_disposition(cursor=0, reused|no-change)` with covering artifacts and may freeze. `create`/`revise` emit `evolution_requested(cursor=0)`. When approval is required, the only next event is `evolution_blocked(cursor=1, approval_required)`, followed by exactly one `evolution_approved(cursor=2)` or `evolution_rejected(cursor=2)`; approval then permits `evolution_applied(cursor=3)`, while rejection permits only `evolution_declined(cursor=3, terminal=true)` and blocks freeze. A rejected request cannot be replaced until that decline exists; the replacement names the declined request. When approval is not required, request transitions directly to `evolution_applied(cursor=1)` and an approval/rejection event is invalid. Instead of either approval path, an owner/provider failure immediately after a request may emit `evolution_blocked(cursor=1, provider_unavailable|authority_rejected, approval_required=false)` and remains blocked. Applied transitions only to `evolution_reviewed(next cursor)`. Review `pass` transitions only to `evolution_disposition(next cursor, created|revised)` and may freeze. Review `fail` transitions only to `evolution_blocked(next cursor, changes_required, approval_required=false)` and remains blocked. A declined or blocked changes-required/provider-unavailable/authority-rejected request can resume only with a new `evolution_requested(cursor=0)` whose `replaces_request_id` names that terminal/blocked request; reuse of the old request ID is forbidden. `evolution_requested` therefore additionally has required `replaces_request_id:id128|null`; it is null only for the first attempt.

Every transition verifies request ID, prior ledger head, event-specific artifact before/after digest, owner trust proof, approval/review record where required, and cursor. A crash resumes at the first missing valid transition, never against an unapproved/newer artifact. Task-scoped reversible artifacts are changed and reviewed only in the approved/no-approval branch, then control returns to `/dr-plan` for refreeze. Framework-wide operating-model changes follow the existing Class B approval boundary. The task cannot enter `/dr-do` until all active requests have a passing disposition and the pinned artifacts exist in the derived freeze commit.

### 6. Evidence model

Every requirement needs load-bearing RED and GREEN events emitted by the framework evidence runner, not hand-authored metadata. They name a shared assertion ID, argv, exit code, observed repository SHA, hermeticity inputs, output digest, and retained evidence path. RED must be non-zero, GREEN zero, and both must name the same load-bearing assertion. The RED record also names the intentional mutation/negative control and the exact assertion that failed; setup, wrapper, or unrelated failures do not count. The runner produces a signed attestation over the command, repository tree, mutation diff, output, and result using a trust root pinned in the consumer registry (`git-ssh-v1`, `sigstore-oidc-v1`, or another shipped verifier profile); an unauthenticated digest alone never proves execution. An independent quality review checks exact-head provenance. Its signed receipt is deliberately external to the reviewed implementation head: it binds repository ID, exact commit/tree, ledger blob/head, reviewer role/key, finding digest, verdict, and timestamp, and is compare-and-appended to the protected receipt authority. Appending the receipt never mutates the reviewed head. A superseding review of a later head creates a new external record; no in-ledger or working-tree receipt may satisfy exact-head review. For migrated work, a present-day mutation or negative control may provide RED; historical RED is never invented. For customer-visible requirements the close gate additionally requires:

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

Trust has two signed layers. The framework catalog `config/customer-delivery-trust-catalog.json` and detached `config/customer-delivery-trust-catalog.json.sig` fix schema/canonicalization versions, minimum verifier/profile versions, permitted algorithms/namespaces/receipt kinds, and recovery rules under the pre-existing Datarim governance root. The concrete Datarim consumer `config/customer-delivery-datarim-registry.json` and detached `config/customer-delivery-datarim-registry.json.sig` reference the exact catalog digest and instantiate repository/project adoption state, `canon_epoch`, providers, signers, scopes, revocation sequence, and monotonic registry predecessor. `templates/customer-delivery-project.json` carries the same consumer schema for downstream projects; the template alone is insufficient. `config/customer-delivery-allowed-signers` is the exact public-key view used by the SSH verifier.

Catalog schema v1 has exactly `schema_version:uint=1`, `catalog_id:id128`, `revision:uint`, `valid_from:utc_seconds`, `valid_until:utc_seconds|null`, `canonicalization_profiles[]`, `receipt_profiles[]`, `minimum_profile_versions[]`, and `recovery_policy`. A canonicalization-profile record has exactly `profile:id128`, `version:uint`, `hash_algorithm:sha256-literal`, and `event_schema_sha256:sha256`; a receipt-profile record has exactly `receipt_type:id128`, `version:uint`, `namespace:id128`, `algorithm:ssh-ed25519-literal`, and `subject_schema_sha256:sha256`; a minimum-version record has exactly `profile:id128` and `minimum_version:uint`; recovery policy has exactly `offline_root_fingerprint:text`, `quorum:uint`, and `record_namespace:id128`. Consumer schema v1 has exactly `schema_version:uint=1`, `registry_id:id128`, `sequence:uint`, `previous_registry_sha256:sha256|null`, `project_id:id128`, `repository_id:id128`, `mode`, `canon_epoch`, `framework_catalog_sha256:sha256`, `allowed_signers_sha256:sha256`, `verifiers[]`, `signers[]`, `providers[]`, `source_commitment_policy`, and `revocations[]`. Mode is `genesis`, `legacy`, `dual-read`, or `strict`; strict cannot revert. `canon_epoch` is null before genesis release or exactly `release_version:text`, `tag_object_oid:git_oid`, `peeled_commit_oid:git_oid`, `ledger_blob_oid:git_oid`, `ledger_head:sha256`, and `anchor_receipt_sha256:sha256`.

A verifier record has exactly `profile:id128`, `platform:id128`, `executable:relative_path`, `version:text`, `executable_sha256:sha256`, and `algorithm:id128`. A signer record has exactly `signer_id:id128`, `key_id:id128`, `fingerprint:text`, `public_key:text`, `identity:id128`, `role:authority_role`, `receipt_types[]:id128`, `namespaces[]:id128`, `repository_scopes[]:id128`, `project_scopes[]:id128`, `task_scopes[]:id128`, `requirement_scopes[]:id128`, `valid_from:utc_seconds`, `valid_until:utc_seconds|null`, `predecessor_key_id:id128|null`, and `status` (`active` or `revoked`). A provider record has exactly `provider_id:id128`, `provider_type:id128`, `executable:relative_path`, `version:text`, `executable_sha256:sha256`, `cwd:relative_path`, `argv_schema_sha256:sha256`, `environment_allowlist[]:id128`, `timeout_minutes:uint`, `output_cap_bytes:uint`, `result_schema_sha256:sha256`, `authentication_subject:id128`, `authentication_audience:id128`, `repository_id:id128|null`, `remote_url:https_url|null`, `protected_ref:text|null`, `ruleset_id:uint|null`, `ruleset_sha256:sha256|null`, `registration_locator:locator`, and `registration_sha256:sha256`; Git authorities require every nullable host field non-null, while non-Git providers require them null. `timeout_minutes` is an integer from 1 through 60. The immutable registration blob contains exactly this provider record and its governance receipt; resolve must retrieve bytes matching `registration_sha256`. Source-commitment policy has exactly `profile:datarim-source-hmac-sha256-v1-literal`, `active_key_ids[]:id128`, and `historical_key_retention:retain-encrypted-indefinitely-literal`. A revocation record has exactly `sequence:uint`, `previous_sha256:sha256|null`, `key_id:id128`, `effective_authority_sequence:uint`, `reason:text`, and `governance_receipt:receipt_ref`. All set-like arrays are canonical-byte sorted and duplicate-free. Unknown keys or enum values fail. The allowed-signers view digest must match the consumer registry and each line must reproduce one active signer without extra principals or namespaces.

Catalog and consumer signatures use distinct namespaces `datarim-trust-catalog-v1` and `datarim-consumer-registry-v1`. A key introduced by a consumer registry cannot authenticate that same registry. Genesis pins the governance SSH fingerprint `SHA256:a3hhUtadjU+KNZ1zI2LQuS88vb+t7YnQUiA4IDNbLgM` outside both artifacts in the reviewed bootstrap; verification first recomputes that fingerprint from the governance public key, verifies the catalog, then verifies the consumer registry against the catalog and predecessor. Ambient Git trust cannot replace this chain. Before freeze, TUNE-0585 provisions distinct private signer identities in the configured non-repository secret store and commits only public entries for `spec-reviewer`, `quality-reviewer`, `evidence-runner`, `project-verifier`, `source-provider`, `deployment-provider`, `visual-provider`, and `release-authority`; governance remains the pre-existing root and GitHub's protected-ref API is the registered anchor provider. The consumer registry fixes the permanent receipt branch/provider locator before any event attestation or final review. No key is reused across mutually exclusive roles, and the implementer/runner cannot hold the reviewer or release key in the respective process. Customer keys are supplied only by a consumer registration and cannot be synthesized by the framework. Private keys, HMAC keys, provider credentials, and customer identities never enter Git.

Every receipt uses canonical schema-v1 payload plus a detached signature envelope. The common payload has exactly `schema_version:uint=1`, `receipt_type:id128`, `receipt_id:id128`, `profile:id128`, `registry_id:id128`, `registry_sequence:uint`, `registry_sha256:sha256`, `canon_epoch` (the exact consumer-record shape or null), `project_id:id128`, `repository_id:id128`, `task_id:id128`, `requirement_id:id128|null`, `subject_sha256:sha256`, `subject`, `provider_sequence:uint|null`, `issued_at:utc_seconds`, and `idempotency_key:sha256`; fields that do not apply are explicit null, never omitted. The detached JSON signature envelope has exactly `schema_version:uint=1`, `payload_sha256:sha256`, `algorithm:ssh-ed25519-literal`, `namespace:id128`, `signer_id:id128`, `key_id:id128`, `principal:id128`, and `sshsig_b64:text`; Base64 is RFC 4648 standard alphabet with padding/no whitespace and decodes to one OpenSSH SSHSIG over the canonical payload bytes.

Receipt subjects are closed. `event-attestation` has exactly `event_id:id128`, `event_index:uint`, `event_hash:sha256`, and `ledger_preimage_sha256:sha256`; `source-manifest` has `manifest_id:id128`, `manifest_head:sha256`, `item_count:uint`, `exhausted:boolean`, `pagination_cursor_sha256:sha256`, and `ordered_commitment_sha256:sha256`; `atomicity-review` has `source_manifest_sha256:sha256`, `requirement_graph_sha256:sha256`, `mapping_cardinality` (the exact event shape), `predecessor_head:sha256`, `spec_revision:git_oid`, and `verdict`; `spec-review` has `reviewed_pair_commit:git_oid`, `prd_blob_oid:git_oid`, `plan_blob_oid:git_oid`, `trust_provision_commit:git_oid`, `finding_sha256:sha256`, and `verdict`; `evolution-approval` has `request_id:id128`, `requested_event_hash:sha256`, `proposal_sha256:sha256`, and `decision:approved-literal`; `evolution-rejection` has `request_id:id128`, `requested_event_hash:sha256`, `proposal_sha256:sha256`, and `reason:text`; `evolution-decline` has `request_id:id128`, `rejected_event_hash:sha256`, and `terminal:true`; `evolution-review` has `request_id:id128`, `artifact_after_sha256:sha256`, `reviewed_event_hash:sha256`, and `verdict`; `quality-review` has `commit_oid:git_oid`, `tree_oid:git_oid`, `ledger_blob_oid:git_oid`, `ledger_head:sha256`, `event_count:uint`, `evidence_manifest_sha256:sha256`, `finding_sha256:sha256`, and `verdict`; `runner-red` and `runner-green` have `assertion_id:id128`, `argv[]` (ordered strings), `tree_sha256:sha256`, `mutation_sha256:sha256|null`, `output_sha256:sha256`, `result_exit_code:int`, `raw_wait_status:uint|null`, `timed_out:boolean`, `termination_signal:uint|null`, `forced_kill:boolean`, and `evidence_path:relative_path`; `project-verification` has `requirement_id:id128`, `red_receipt_sha256:sha256`, `green_receipt_sha256:sha256`, and `disposition:verified-literal`; `customer-disposition` has `authority_record_id:id128`, `requirement_id:id128`, `deployed_sha:git_oid`, `disposition`, `private_commitment:sha256`, and `private_locator:locator`; `deployment` has `requirement_id:id128`, `source_sha:git_oid`, `deployed_sha:git_oid`, and `provenance_sha256:sha256`; `visual` has the exact visual-observation payload without `authority`; `authorization` has `freeze_commit:git_oid`, `repository_id:id128`, `clean_base_sha:git_oid`, `marker_commit:git_oid`, and `marker_sha256:sha256`; `reconciliation` has `conflicts[]:conflict_ref` and `chosen_successor_event_id:id128`; `anchor` has `event_head:sha256`, `event_count:uint`, `ledger_blob_oid:git_oid`, `byte_length:uint`, `provider_ref:text`, `provider_commit_oid:git_oid`, and `previous_receipt_sha256:sha256|null`; `release-tag` has `release_version:text`, `reviewed_pr_head:git_oid`, `merged_commit_oid:git_oid`, `tree_oid:git_oid`, `ledger_path:relative_path`, `ledger_blob_oid:git_oid`, `ledger_byte_length:uint`, `event_count:uint`, `ledger_head:sha256`, `quality_receipt_locator:locator`, `quality_receipt_sha256:sha256`, `ruleset_id:uint`, `ruleset_sha256:sha256`, `verifier_profile:id128`, `verifier_version:text`, and `verifier_executable_sha256:sha256`. Each receipt type has one fixed catalog namespace. Wrong class, role, namespace, scope, registry revision, provider sequence, or subject binding fails even under a valid key. `config/customer-delivery-receipt-v1.schema.json`, `config/customer-delivery-trust-catalog-v1.schema.json`, and `config/customer-delivery-project-v1.schema.json` are exact executable transcriptions, not extensible policy.

Genesis bootstrap uses only pre-existing executables registered in `config/customer-delivery-bootstrap-provider-v1.json` plus its detached governance signature. That closed record has exactly `schema_version:uint=1`, `registration_id:id128`, `reviewed_pair_commit:git_oid`, `python_executable:text`, `python_version:text`, `python_sha256:sha256`, `validation_script_b64:text`, `validation_script_sha256:sha256`, `ssh_keygen_executable:text`, `ssh_keygen_version:text`, `ssh_keygen_sha256:sha256`, `git_executable:text`, `git_version:text`, `git_sha256:sha256`, `gh_executable:text`, `gh_version:text`, `gh_sha256:sha256`, `environment_allowlist[]:id128`, `working_directory:relative_path`, `command_templates[]`, and `governance_receipt:receipt_ref`. Each command template has exactly `operation:id128`, `argv[]` (ordered text), `stdin_profile:id128|null`, and `expected_exit_codes[]:uint`. `validation_script_b64` is the exact `/usr/bin/python3 -I -c` script, encoded with the receipt Base64 rules; it performs duplicate-key rejection, closed-key/type/range checks, canonicalization, digest computation, and emits no secret value. No downloaded or working-tree executable participates. The signed immutable registration blob is created before trust/receipt use and its exact locator/digest is bound by every genesis provider record.

Catalogs, consumer registries, revocations, receipts, and their public keys remain retrievable as immutable blobs on the monotonic authority; a valid signature on a replayed older registry is insufficient. Rotation requires an old-and-new continuity signature or an explicit offline governance recovery record; compromise recovery cannot rely on the compromised old key. Revoked/expired keys invalidate new receipts. Historical receipts remain valid only when their immutable provider sequence predates the revocation boundary; timestamps alone never establish that. Profile downgrade is forbidden after `canon_epoch`. The verifier resolves the historical signed catalog/registry/revocation sequence named by each event or receipt and rejects authority material merely present in the same untrusted tree.

The first shipped provider profiles are concrete:

- `git-protected-ref-v1` is the ongoing monotonic receipt/head authority. It requires a dedicated remote branch whose current host rules forbid deletion and non-fast-forward updates while permitting append-only fast-forwards, verifies those rules through a pinned host API profile on every append/resolve gate, and accepts a receipt or ledger head only when the exact immutable blobs are reachable from that protected ref. Datarim's concrete registry fixes `refs/heads/datarim/customer-delivery-receipts-v1`, its exact GitHub ruleset ID/digest after creation, and the immutable provider-registration blob; downstream projects choose their own exact protected ref. Each strict stage transition compare-appends through this authority before the next stage. Git credentials come from the existing credential helper; tokens are never command arguments.
- `git-immutable-tag-v1` is the one-shot genesis/release anchor. It requires a protected `refs/tags/v*` namespace whose rules, refetched after tag creation, forbid deletion, non-fast-forward, and update with no bypass. A distinct registry signer role `release-authority` is authorized for namespace `git` solely for the embedded SSH tag signature required by `git verify-tag`, and for namespace `datarim-release-v1` for the separate closed `release-tag` receipt embedded in the annotation. Both validations bind the same public key/fingerprint and immutable authority locator; neither namespace substitutes for the other. The canon's reviewed release tag anchors the final genesis tuple but cannot serve subsequent append transitions.
- `git-ssh-v1` authenticates runner/reviewer receipts with `ssh-keygen -Y sign/verify`, a fixed namespace per receipt class, and a project-registry allowed-signers file pinned by digest and scoped as above. Private keys stay in the configured agent/CI signer; the registry stores public identities only.
- source, customer, and child providers use the same constrained adapter envelope and an authenticated provider-specific receipt. A project without a passing trust/authority probe cannot arm strict mode.

The plan must perform one hard outer eight-minute feasibility probe of executable availability, signer verification, remote rules, credential scope, and an append/resolve dry run before implementation. All provider and evidence-runner deadlines are expressed as integer minutes, never ambiguous seconds. A dedicated negative-control command has a one-minute child deadline within that longer probe and passes only when the supervisor sends SIGTERM to the child process group and records normalized process exit `143` (`128 + SIGTERM`), `raw_wait_status`, `termination_signal:15`, `timed_out:true`, and no surviving descendant; this expected negative result does not make the overall probe fail. An unexpected deadline on any ordinary probe command is a failure and is never collapsed into a generic error. A child that does not terminate during the fixed five-second cleanup grace is force-killed, with `forced_kill:true` and raw wait status retained, while the contracted deadline result remains exit `143`. Documentation is not proof of provider behavior.

Adapters are data providers, never shell fragments or state authorities. Registration is accepted only from the project-governance location and authority pinned by the framework consumer registry. It uses argv arrays with an allowlisted executable, pinned executable digest/version, fixed project-relative working directory, explicit environment allowlist, an integer-minute deadline, stdout-size cap, and authenticated/schema-validated JSON results. The validator invokes without a shell, rejects path escapes and symlinks, applies the SIGTERM/exit-143 deadline contract above, and independently recomputes coverage. Adapters cannot emit derived state or passing assertions. A customer-authority adapter may resolve an existing signed acceptance record but cannot create one; the core verifies its trust proof. The separate head-anchor adapter exposes append/resolve operations backed by a monotonic provider and rejects rollback or divergent heads.

### 10. Writer durability and authority transitions

The writer serializes per-task appends with an advisory lock that carries owner/process/start metadata and a bounded stale-lock recovery rule. It validates the current anchored head, writes and fsyncs a complete temporary file, atomically renames, fsyncs the containing directory, publishes the complete immutable blob, then requests a compare-and-append head receipt. Duplicate retries are idempotent by event ID and payload digest. Concurrent/divergent predecessors fail without overwriting either branch. Disk-full, short write, signal/process death, publication/anchor timeout, and failure between rename/publication/anchor leave an explicit recoverable `unanchored` state; no stage gate passes until reconciliation proves the exact published blob and anchors it.

Supersession is deterministic. `event_superseded` may target only `lane_classified`, `source_manifest_bound`, `requirement_declared`, `production_ac_declared`, `parent_intent_bound`, `child_manifest_bound`, `evolution_disposition`, or `prework_contract_frozen`; it must occur before any valid `implementation_authorized`, use governance authority, point to an already-present same-typed replacement event, and list the exact downstream review/freeze invalidation set. Every other target type or actor fails. Remark captures, atomicity reviews, evolution history, authorization, implementation/evidence/deploy/visual observations, dispositions, reconciliations, legacy claims, and external receipts are never semantically removed. A declaration supersession invalidates atomicity review/freeze and all downstream events.

Implementation/evidence/deploy/visual observations are countermanded only by a newer valid observation with the same typed subject identity and scoped runner/provider signer; the highest `event_index` on one reconciled anchored chain wins. Customer disposition is resolved by customer-provider sequence, never ledger order, and returned/rejected reopens. Two events with the same predecessor are a divergence and neither wins. `head_reconciled` is appended only to the authority-chosen branch, contains canonical-sorted `conflict_ref` pairs for every conflicting event/head, requires equal shared predecessor and at least two pairs, chooses exactly one paired event ID, and carries a `reconciliation` receipt signed by `reconciliation-authority`; the external authority preserves every losing blob/head. A reconciliation missing a branch, inventing an association, or choosing a non-member fails closed.

### 11. Genesis bootstrap

A framework cannot use an unimplemented runner/anchor to prove its own creation. The sole bootstrap is explicit and non-passing:

1. An exact PRD/plan commit exists first; no canonical review receipt is claimed yet.
2. A trust-provision commit, signed by the pre-existing pinned governance root, creates the closed catalog, Datarim consumer registry in `genesis` mode with null epoch, allowed-signers view, role assignments, permanent protected receipt-ref identity, and their detached signatures. These are pre-work authority artifacts, not implementation source.
3. A subordinate spec reviewer reviews the unchanged exact PRD/plan commit using the provisioned reviewer identity. Its canonical payload and detached signature bind the now-existing trust-provision registry digest/sequence. No future-registry placeholder is permitted.
4. A separate genesis-freeze commit records that review receipt/signature, private-source commitments, atomic requirement mapping/review, all existing pinned capabilities, target base, provider feasibility, and selected profiles. It may not pin a skill or tool that does not yet exist.
5. A marker commit in the implementation repository records the clean target base. The authorization event/receipt then binds the known freeze and marker commits without naming its own containing commit; a separate authorization-event commit completes the pre-work gate. Ordinary repository TDD then drives the initial implementation; raw Bats outputs are development evidence, not canonical runner attestations.
6. Once the runner exists, a present-day controlled mutation produces canonical signed RED, the restored exact head produces signed GREEN, and all final ledger/evidence changes are committed. An independent quality reviewer then signs an external exact-head receipt and compare-appends it to the permanent protected receipt authority; the implementation head does not change after review.
7. The bootstrap remains `genesis_unanchored` and cannot report canonical completion until that exact reviewed head is merged, the signed release tag annotation binds the full merged commit/tree and ledger blob/event head/count, the current immutable-tag ruleset still forbids deletion/update/non-fast-forward with no bypass, and an independent verifier refetches the ruleset, tag/receipt, and ledger bytes through `git-immutable-tag-v1`. The verified external tag receipt compare-appends the Datarim external registry epoch and becomes `canon_epoch`; it is sufficient without a recursive in-ledger or next-release Git commit. All later tasks use the normal strict sequence with the permanent `git-protected-ref-v1` receipt branch.

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

New L1-L4 tasks classify their lane after the exact framework release/version/commit recorded as `canon_epoch`. Armed lanes are hard across all complexity levels. The consumer registry, outside the task ledger, records a monotonic adoption state that cannot revert from strict to legacy or `none`. Pre-epoch tasks are historical unless explicitly registered for strict adoption. A migration helper imports genuine source bytes as capture events, labels retroactive seeds as `legacy_unverified_source`, and imports existing implementation/tests/screenshots/deploy text only as `legacy_claim_imported` events that do not satisfy coverage. It never invents remarks, bindings, RED/GREEN, live proof, or dispositions. Dual-read compatibility lasts exactly one release and has a named removal version.

Migration is byte-deterministic and split into plan/apply. Planning is `migrate --plan --mode genesis|legacy-v0 --task <id> --project <id> --input <migration-input-json> --source-snapshot <signed-manifest-json> --registry <signed-consumer-json> --authorization-commit <full-sha-or-null> --canon-epoch <version@full-sha-or-null> --compatibility-release <version-or-null> --removal-version <version-or-null> --recorded-at <UTC-seconds> --event-signer <signer-id> --receipt-output <relative-dir> --output <migration-plan-json>`. Apply is `migrate --apply --plan <migration-plan-json> --plan-sha256 <lowercase-hex> --input <migration-input-json> --source-snapshot <signed-manifest-json> --registry <signed-consumer-json> --event-signer <signer-id> --receipt-output <relative-dir> --output <ledger-jsonl>`. All paths are project-root-confined regular files. Planning and apply read no wall clock; planning reads no network, and apply performs only the registered receipt compare-append/refetch operations after verifying the locally resolved immutable source snapshot, input, and registry bytes.

Migration schema v1 is closed in `config/customer-delivery-migration-v1.schema.json`. A source snapshot has exactly `schema_version:uint=1`, `provider_id:id128`, `provider_sequence:uint`, `manifest_id:id128`, `manifest_head:sha256`, `items[]`, `item_count:uint`, `pagination_cursor_sha256:sha256`, `ordered_commitment_sha256:sha256`, `exhausted:true`, `anchor_receipt:receipt_ref`, and `signature:receipt_ref`. A source item has exactly the `remark_captured` payload fields other than `authority`, in provider order. A migration input has exactly `schema_version:uint=1`, `mode`, `project_id:id128`, `task_id:id128`, `lane`, `parent_intent` (`parent_intent_bound` payload without authority or null), `source_items[]`, `requirements[]`, `production_acs[]`, `atomicity_review` (payload without authority), `evolution_events[]` (closed event payloads without authority), `prework_contract` (payload without authority), `authorization` (payload without authority or null for legacy), and `legacy_claims[]` (legacy payloads without authority). Requirements and ACs use their exact event payload schemas without authority. Arrays preserve the authenticated provider or declared semantic order; counts/digests must match.

A migration plan has exactly `schema_version:uint=1`, `profile:migration-v1-literal`, `mode`, `project_id:id128`, `task_id:id128`, `input_sha256:sha256`, `source_snapshot_sha256:sha256`, `registry_sha256:sha256`, `registry_sequence:uint`, `authorization_commit:git_oid|null`, `canon_epoch` (consumer epoch shape or null), `compatibility_release:text|null`, `removal_version:text|null`, `recorded_at:utc_seconds`, `event_signer:id128`, `receipt_output:relative_path`, `provider_sequence:uint`, `ordered_input_sha256:sha256`, `events[]`, `event_count:uint`, `ledger_byte_length:uint`, `ledger_sha256:sha256`, `ledger_head:sha256`, `coverage_classification:id128`, and `findings[]`. Each plan event has exactly `semantic_source_id:id128`, `event` (one complete closed schema-v1 event object including `event_hash`), and `event_attestation_id:id128`; each finding has exactly `code:id128`, `subject_id:id128`, and `message:text`. The concatenation of canonical `event` objects plus one LF each must exactly match the planned ledger byte length/SHA/head, so apply can reconstruct the ledger from the plan while independently comparing the supplied source/input/registry digests. Unknown keys fail.

The immutable plan contains all input SHA-256 values, provider sequence/head, exact epoch/tag/object/commit where applicable, compatibility/removal versions, fixed type precedence, every intended event ID/index, output byte length/SHA-256/event count/head, coverage classification, and findings. Event order is fixed by type precedence, stable pseudonymous source item ID, claim kind, locator, and digest. Each event ID is `mig:` plus lowercase SHA-256 of canonical JSON containing migration profile, all input digests, pseudonymous source identity or singleton semantic ID, event type, and zero-based ordinal. Native provider IDs never seed public identifiers. Genesis uses the bootstrap's exact frozen records and authorization commit; legacy commitments are recomputed through the registered private provider.

Planning writes no ledger or event receipt. Apply rejects source/input/registry drift, recomputes the plan and intended bytes, asks the registry-scoped event signer for one canonical `event-attestation` per event, writes payload/signature pairs to `receipt_output`, compare-appends them to the permanent receipt authority by idempotency key, and refetches/verifies every tuple before installing the ledger. Missing/wrong-role attestations fail even in `unanchored` genesis. Apply then builds and validates complete ledger bytes in a root-confined temporary sibling, fsyncs them, refuses an existing non-identical target, treats identical target/receipts as idempotent success, atomically renames, and fsyncs the directory. Provider timeout, pagination gap, plan-digest mismatch, ID collision with different semantics, invalid mapping, receipt failure, partial write, or validation failure leaves the target unchanged. Because attestations are append-only, failure after their publication leaves them in explicit `pending-orphan` state keyed by plan digest; they are not passing evidence and cannot authorize a stage until an identical retry installs and validates the named ledger, after which they become `bound`. A recovery manifest records each published/refetched receipt and target-install state. Replaying identical inputs produces byte-identical plan and ledger bytes and the same receipt idempotency keys. Migration never anchors the ledger head automatically; after event validation it remains `unanchored` until normal provider publish/resolve succeeds. Only then may the external consumer registry owner compare-and-swap through the provider's exact argv-only `registry-cas` operation from `legacy` to the one-release dual-read state and later to irreversible `strict`; the request binds expected registry sequence/digest, replacement signed registry digest, and anchor receipt. A crash after anchor but before registry CAS resumes from anchor resolution without remigration.

#### D-REQ-10: Security and evidence preservation

Verbatim external text is treated as data, never executed. CLI text inputs use files or JSON stdin, paths are root-confined, commitments are recomputed through the private provider, symlinks cannot escape the project root, and reports never print secrets or provider-native identifiers. Evidence paths are durable and project-relative; `/tmp` cannot satisfy retention.

#### D-REQ-11: Project registration and adapter boundary

The core validator remains project-agnostic. A governance-signed registration schema defines exact contract roots, authoritative source/child manifests, surface matrices, constrained adapter argv, disjoint signer roles/scopes, verifier revisions, revocation/rotation policy, and customer authority. Missing, mutable, unsafe, downgraded, unauthorized, revoked, non-executable, timed-out, oversized, or schema-invalid adapters/receipts fail only the phases that need them.

#### D-REQ-12: Honest genesis and independent reviews

TUNE-0585 follows five ordered signed pre-code commits—exact PRD/plan pair, trust provision, freeze, authorization marker, and authorization event—before implementation, labels raw TDD as development-only, captures a present-day signed mutation RED and restored GREEN after the runner exists, passes focused/full suites, and receives subordinate exact-blob spec review before source work and exact-head quality review after implementation. It cannot claim canonical completion until the resulting head is merged and anchored on the selected protected ref.

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

Exact `canon_epoch`, one-release dual read, strict-mode non-reversion, genuine-source import, and `legacy_claim_imported` non-coverage fixtures pass independently. Ambient-clock/network access, byte/order drift, missing or wrong-role event attestations, changed source/registry between plan/apply, existing-identical versus existing-different target, plan replay non-identity, temp/short-write/fsync failure, anchor-before-registry-CAS inversion, crash-after-anchor resume, and registry-CAS stale-sequence mutants each fail at their named boundary without changing an acknowledged target.
Covers: D-REQ-09

### V-AC-8 — Runner and adapter safety

Argv/no-shell controls, executable/registration trust, integer-minute timeout/output/env caps, an over-deadline process group with a spawned grandchild that is terminated and observed as normalized exit `143` with SIGTERM attribution, a SIGTERM-resistant control that records raw wait status and `forced_kill:true` without leaking a descendant, path confinement, commitment checks, forged/hash-only runner receipts, wrong-role/scope/audience/namespace, expired/revoked/downgraded profiles, forged customer dispositions, authenticated result validation, and evidence-receipt provenance mutations pass.
Covers: D-REQ-05, D-REQ-10, D-REQ-11

### V-AC-9 — Genesis and review

TUNE-0585's exact reviewed PRD/plan pair, trust provision, genesis freeze, authorization marker, and authorization event are five ordered signed commits before implementation; raw TDD is not canonical evidence; present-day signed mutation RED/restored GREEN, focused/full exact-head validation, English-only surface, exact-blob spec-review disposition, external non-recursive exact-head quality-review receipt, embedded Git-namespace tag signature, separate `datarim-release-v1` receipt, and post-merge refetch/verification of current host rules plus full tag/commit/tree/ledger blob/event head/count are independently verified.
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
- **Privacy leak:** public ledgers retain only versioned HMAC commitments and opaque locators by default; verbatim bytes and HMAC keys remain in the registered private source provider.
- **Artifact explosion:** one task-level JSONL ledger and retained evidence directories keep the model bounded.
- **Legacy noise:** the pivot is default-strict for new tasks and opt-in strict for pre-pivot tasks.
- **Customer authority ambiguity:** registration names accepted authority kinds; agents cannot author `accepted` dispositions unless explicitly authorized.

## Downstream Boundary

This PRD is complete when the universal mechanism is released. It does not claim that Talomnia is delivered. TALO-0001 remains open until its imported requirement graph, sixteen canonical White Paper figures, product implementation, exact deployment, live screenshot matrix, and customer dispositions pass the new derived coverage gate.
