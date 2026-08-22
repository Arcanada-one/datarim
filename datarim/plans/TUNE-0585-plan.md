---
task_id: TUNE-0585
artifact: plan
status: approved
created: 2026-08-22
prd: datarim/prd/PRD-TUNE-0585.md
blueprint_revision: 992ee15401d8f9cc28859c2790e030f8d160e839
exact_base: d27b15f390265fef1fc95c31a28677a9664acb98
spec_review_status: external_receipt_required
---

# Universal Customer-Delivery Canon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `subagent-driven-development` to execute this plan task-by-task, with a specification check after each implementation task and an independent exact-head quality review before completion.

**Goal:** Ship a universal, fail-closed Datarim customer-delivery ledger that preserves authoritative customer remarks, enforces pre-work attribution and review-to-evolution, captures load-bearing evidence, derives task/epic state from closed-world coverage, and prevents user-facing completion from tools or tests alone.

**Architecture:** A standard-library Python core owns an append-only SHA-256 event ledger, constrained provider adapters, a runner-produced evidence receipt, phase validation, migration, and derived state. A thin shell gate exposes stable lifecycle exit codes. A shared skill and reference define the semantics; every task-creating/advancing command declares and enforces its phase behavior. Human expectations remain a compatibility view, never closure authority for armed lanes.

**Tech Stack:** Python 3 standard library, Bash, Bats, Markdown command contracts, JSON/JSONL, Git object/ancestry checks, `ssh-keygen -Y` signatures, and the GitHub repository-rules API for the first `git-protected-ref-v1` profile.

---

## Overview

The operator-approved sequence requires the reusable enforcement layer before any Talomnia adoption. This plan first closes the canon's honest genesis, then implements the deterministic ledger and trust boundary test-first, propagates it through every advancing command, proves it on exact head, and only then establishes the immutable release epoch. It does not claim Talomnia delivery.

## Architecture Impact

This adds one shared validation seam rather than replacing PRD, expectations, spec graph, QA, or compliance. Armed tasks gain a private HMAC source provider, a public event ledger, signed evidence receipts, an immutable content-addressed ledger blob, and an external protected-ref anchor receipt. Existing tasks remain historical until an exact `canon_epoch`; armed adoption is monotonic. Commands stay Markdown contracts, while the Python core is the sole parser/deriver and the shell wrapper is the stable invocation boundary.

## Detailed Design

Tasks 2-5 implement ledger/durability, provider trust, evidence, migration, and derived state. Tasks 6-8 wire every task-advancing command and close quick/content/replay bypasses. Task 9 publishes the reference, runs all gates, and establishes the protected-ref release epoch. The PRD is normative for event fields, authority semantics, state transitions, and the one-time genesis exception.

## Security Summary

- Private verbatim bytes never enter the public ledger by default; reports use pseudonymous IDs, versioned domain-separated HMAC commitments, and opaque locators.
- Adapters and the evidence runner are argv-only, no-shell, root-confined, time/output/env bounded, and authenticated against pinned trust roots.
- Strict state requires a remote ref verified to reject deletion/non-fast-forward/update; local chain validity is insufficient.
- External text is data and never executed. Secrets remain in credential helpers/signer stores, never argv, logs, fixtures, or committed config.
- S1/S2/S3/S5/S9/S10 apply, and S11 requires a distinct adversarial review because external provider bytes cross into agent-readable evidence.

## Security Design and Threat Model

The defended failures are omitted/private-source mutation, offline dictionary recovery, forged/wrong-role evidence or customer acceptance, registry/profile downgrade, adapter command injection, credential leakage, missing acknowledged blob bytes, ledger rollback/truncation/divergence, ambiguous/unauthorized supersession, symlink/path escape, concurrent writers, crash/disk-full loss, and post-hoc attribution. The trust roots are the governance-signed consumer registry's scoped allowed signers and a host-protected Git ref. A project whose rules/signature/provider probe fails cannot arm strict mode. The framework cannot prevent deliberate unrecorded work, but it makes that work ineligible for canonical evidence and independently reviewable.

## Immutable pre-work contract

Before Task 2 changes implementation source, freeze the following for TUNE-0585 in `datarim/delivery/TUNE-0585.bootstrap.json` `[to-be-created]` and commit it separately:

- role: `developer` plus subordinate `peer-reviewer` for specification and quality gates;
- skills: `testing`, `ai-quality`, `security-baseline`, `subagent-driven-development`, `verification-before-completion`, `requesting-code-review`;
- blueprint: `PRD-TUNE-0585` at exact commit recorded in frontmatter after the PRD-only commit; no alternative or mutable revision is permitted;
- constraints: English-only shipped surface, stdlib-only parser, no shell adapter execution, root-confined paths, no fabricated legacy evidence, protected-branch PR flow;
- policies: `CLAUDE.md`, security baseline, workspace discipline, and operator amendment; the not-yet-created customer-delivery skill is a deliverable, never a bootstrap pin;
- success criteria: V-AC-1 through V-AC-10 in the PRD;
- enabling parent intent: `TALO-0001/C-REQ-DELIVERY-CANON`, bound to the authenticated operator amendment; later Talomnia registration must reconcile the exact project/task/requirement identity, without treating framework artifacts as visitor-visible delivery.

Genesis separates specification, trust provision, contract base, freeze, authorization marker, and authorization-event commits because no artifact may name the commit that contains itself and the framework cannot self-attest before its runner exists. The permanent external receipt authority and signed registry exist before the exact-head specification receipt; the contract-base commit makes the requirement-scoped manifest independently addressable; the freeze binds that receipt, manifest, and provider proof; the marker names the freeze; and the authorization event plus detached authorization receipt name the already-existing marker. Implementation begins only in a descendant of the authorization-event commit. Raw TDD proves development sequencing but is not canonical evidence. After the runner exists, a present-day mutation/restoration supplies signed canonical RED/GREEN, and the verified protected release plus registry-successor CAS becomes the monotonic `canon_epoch`.

## Implementation Steps

### Task 1: Close specification and bootstrap dogfood provenance

**Files:**

- Modify: `datarim/prd/PRD-TUNE-0585.md`
- Modify: `datarim/tasks/TUNE-0585-task-description.md`
- Modify: `datarim/tasks/TUNE-0585-expectations.md`
- Create: `datarim/delivery/TUNE-0585.bootstrap.json` `[to-be-created]`
- Create: `datarim/delivery/TUNE-0585.contract-manifest.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/spec-review.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/spec-review.json.sig` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/provider-feasibility.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/provider-raw/` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/provider-cleanup.jsonl` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/event-receipts/` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/migration-recovery.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/authorization-receipt.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/authorization-receipt.json.sig` `[to-be-created]`
- Create: `datarim/delivery/TUNE-0585.authorization-marker.json` `[to-be-created]`
- Create: `config/customer-delivery-trust-catalog.json` `[to-be-created]`
- Create: `config/customer-delivery-trust-catalog.json.sig` `[to-be-created]`
- Create: `config/customer-delivery-datarim-registry.json` `[to-be-created]`
- Create: `config/customer-delivery-datarim-registry.json.sig` `[to-be-created]`
- Create: `config/customer-delivery-allowed-signers` `[to-be-created]`
- Create: `config/customer-delivery-bootstrap-provider-v1.json` `[to-be-created]`
- Create: `config/customer-delivery-bootstrap-provider-v1.json.sig` `[to-be-created]`
- Create: `config/customer-delivery-provider-registrations/` `[to-be-created]`

**Steps:**

1. Resolve `approved_pair_commit` as the exact signed HEAD on which both preliminary subordinate reviewers returned YES; it must contain the exact plan blob under review and separately record the PRD blueprint revision from frontmatter. The trust-provision commit must descend from `approved_pair_commit`, never merely from the PRD-only parent. Register only pre-existing absolute executables through `config/customer-delivery-bootstrap-provider-v1.json`: `/usr/bin/python3 -I -c <decoded-exact-script>`, `ssh-keygen`, `git`, and the resolved `gh`, with exact version/digest/argv templates, environment, and cwd; its detached signature uses the pinned governance key/`datarim-bootstrap-provider-v1` directly and no pre-registry common receipt. Provision distinct non-repository private identities for `registry-owner`, `spec-reviewer`, `atomicity-reviewer`, `evolution-owner`, `evolution-reviewer`, `quality-reviewer`, `evidence-runner`, `project-verifier`, `source-provider`, `deployment-provider`, `visual-provider`, `reconciliation-authority`, `anchor-authority`, and `release-authority`. Store each provider's unsigned, non-self-referential canonical registration payload and detached governance signature under `config/customer-delivery-provider-registrations/`; registry records bind separate payload locator/digest and signature locator/digest fields. Commit only bootstrap/provider registrations and signatures, public assignments, closed trust catalog, Datarim consumer registry in `genesis` mode, derived allowed-signers view, and detached governance signatures in a signed trust-provision commit. The registry must bind governance fingerprint `SHA256:a3hhUtadjU+KNZ1zI2LQuS88vb+t7YnQUiA4IDNbLgM`, the exact event/receipt-to-role tables, release authority namespaces `git` and `datarim-release-v1`, and permanent receipt authority `refs/heads/datarim/customer-delivery-receipts-v1` with repository/remote/ref, immutable payload/signature registration locators/digests, exact GitHub ruleset ID/digest, deletion/non-fast-forward rules, and no bypass. Create and read back that branch/ruleset before any event attestation. This is pre-work authority material, not implementation source.
2. Obtain a subordinate exact-blob review of the unchanged PRD/plan pair after the trust-provision commit. Materialize both `spec-review.json` and detached `spec-review.json.sig` using the closed `spec-review` common receipt/signature envelopes; bind `approved_pair_commit`, its exact PRD/plan blob IDs, the already-existing registry revision/digest, trust-provision commit, finding digest, verdict, spec-reviewer key, namespace, scope, and provider sequence. Compare-append and refetch that receipt from the permanent protected authority. If either reviewer returns NO, revise and commit the specification, replace the dependent trust provision/registry revision without rewriting history, and repeat both preliminary and canonical reviews. Do not edit implementation source before two YES verdicts bind the same exact pair commit.
3. Before any implementation source or RED test is created, complete one hard outer eight-minute feasibility probe of the concrete genesis and ongoing profiles. A dedicated one-minute negative-control command spawns a child and grandchild; it passes only when the supervisor signals the process group and records normalized exit `143`, raw wait status, `termination_signal:15`, `timed_out:true`, `forced_kill`, and no surviving descendant. A second SIGTERM-resistant control must exercise the five-second grace/forced-kill branch without leaking a descendant. Expected timeout-control exits do not fail the outer probe; any unexpected exit `143` on an ordinary command does. The replay below covers signer behavior and immutable-tag resolution; the same report must also contain a disposable hosted append/resolve probe that proves current admin/write/read credential scope. Create a uniquely named temporary branch from the reviewed pair head, create/read back a GitHub ruleset targeting only that exact branch with `deletion` and `non_fast_forward` rules and no bypass actor, push a first commit containing a synthetic immutable ledger blob, and push one append-only fast-forward. Then issue an actual remote forced update with `git push --force-with-lease=<full-ref>:<known-remote-oid> origin <ancestor>:<full-ref>` and an actual remote deletion with `git push origin :<full-ref>`; both must reach GitHub and fail with the named ruleset/rule ID, not client fast-forward checks, auth, hooks, or malformed argv. Clone into a new empty repository and recompute the full branch commit OID, ledger Git blob OID, byte length, event count, and event head from fetched bytes. Retain redacted raw API/Git response bytes under `provider-raw/` and record their digests plus every exact argv, exit code, start/end time, and attribution assertion. The disposable branch remains protected until cleanup; the permanent receipt branch remains protected indefinitely. Any failed API/write/read/rejection/resolve blocks the freeze and all source work.

   The local/tag replay substitutes only the temporary-directory value:

   ```bash
   probe_dir="$(mktemp -d)"
   ssh-keygen -q -t ed25519 -N '' -f "$probe_dir/signer"
   printf 'datarim-provider-probe-v1\n' >"$probe_dir/payload"
   ssh-keygen -Y sign -f "$probe_dir/signer" -n datarim-provider-probe "$probe_dir/payload"
   printf 'probe@example.invalid namespaces="datarim-provider-probe" %s\n' "$(cat "$probe_dir/signer.pub")" >"$probe_dir/allowed_signers"
   ssh-keygen -Y verify -f "$probe_dir/allowed_signers" -I probe@example.invalid -n datarim-provider-probe -s "$probe_dir/payload.sig" <"$probe_dir/payload"
   gh api repos/Arcanada-one/datarim/rulesets/16418778 >"$probe_dir/release-ruleset.json"
   gh api repos/Arcanada-one/datarim/rulesets/15879567 >"$probe_dir/default-ruleset.json"
   git -C "$probe_dir" init -q tag-resolver
   git -C "$probe_dir/tag-resolver" fetch --no-tags https://github.com/Arcanada-one/datarim.git refs/tags/v2.66.2:refs/tags/v2.66.2
   git -C "$probe_dir/tag-resolver" rev-parse refs/tags/v2.66.2
   git -C "$probe_dir/tag-resolver" rev-parse 'refs/tags/v2.66.2^{}'
   git -C "$probe_dir/tag-resolver" cat-file -p refs/tags/v2.66.2
   git -C "$probe_dir/tag-resolver" cat-file -t 'refs/tags/v2.66.2^{}'
   ```

   Materialize `provider-feasibility.json` from captured outputs with `apply_patch` before freeze; the report is not implicit output. Its closed top level has exactly `schema_version:uint=1`, `probe_id:id128`, `pair_commit:git_oid`, `registry_revision:uint`, `started_at:utc_seconds`, `ended_at:utc_seconds`, `outer_deadline_minutes:uint=8`, `commands[]`, `rulesets[]`, `published`, `resolved`, `raw_artifacts[]`, `cleanup_state`, `verdict`, and `authority`. A command has exactly `argv[]` (ordered text), `deadline_minutes:uint`, `result_exit_code:int`, `raw_wait_status:uint|null`, `timed_out:boolean`, `termination_signal:uint|null`, `forced_kill:boolean`, `descendants_survived:boolean`, `stdout`, `stderr`, and `assertion_id:id128`; stdout/stderr/raw-artifact records each have exactly `path:relative_path`, `sha256:sha256`, `byte_length:uint`, and `redacted:boolean`. A ruleset record has exactly `ruleset_id:uint`, `scope:text`, `rules[]:id128`, `bypass_count:uint`, and `raw_artifact_sha256:sha256`. Published/resolved each have exactly `branch_ref:text`, `commit_oid:git_oid`, `ledger_blob_oid:git_oid`, `byte_length:uint`, `event_count:uint`, and `event_head:sha256`; cleanup state is `pending` or `complete`, verdict is `pass` or `fail`, and authority is the closed authority record. Validate duplicate-key rejection, every timeout cross-field rule, `outer_deadline_minutes == 8`, one-minute exit-143/SIGTERM process-group/grandchild controls including the resistant forced-kill branch, and the same semantic assertions: release ruleset `16418778` remains observation only; disposable rules are exact/no-bypass; initial/fast-forward pushes pass; forced/deletion pushes reach the remote rule and fail; clean-clone values equal published. The 2026-08-22 read-only probe already confirmed SSH/API/tag resolution but does not substitute for hosted write scope.
4. On probe failure, before any freeze, immediately remove the disposable ruleset and branch using the private durable recovery manifest, retain the redacted raw provider bytes and failure report outside the candidate branch, prove absence by API/refetch, and import those raw bytes plus their digests into `provider-raw/` and the later immutable cleanup log before retry. A failed freeze must never strand hosted resources or reduce the record to self-asserted digests. On success, leave the disposable resources protected and commit their raw bytes/report only as part of the next freeze.
5. Create `TUNE-0585.contract-manifest.json` with every active framework requirement exactly once; each requirement binding names deterministic IDs for its earlier-in-ledger parent-intent/evolution-disposition events and non-empty immutable role/skill/blueprint/constraint/policy/success-criterion arrays. Commit that manifest alone as a signed contract-base commit. Then create `TUNE-0585.bootstrap.json` with private operator-amendment source provenance, atomic framework requirements/review, requirement-scoped `enabling-v1` parent intent `TALO-0001/C-REQ-DELIVERY-CANON`, requirement-scoped evolution dispositions, selected provider profiles, explicit migration time, and exact catalog/registry/provider/spec-review/contract-manifest digests. Its `prework_contract_frozen` payload names the contract-base commit and existing manifest artifact ref, while the referenced parent/evolution IDs resolve earlier in the freeze ledger; it never names the containing commit. Commit the bootstrap, spec-review receipt/signature, feasibility report/raw bytes, and initial cleanup log as the separate signed freeze commit; derive `freeze_commit` as the first descendant containing that exact freeze ledger/blob.
6. After verifying the signed freeze and every committed digest, delete only the disposable ruleset, then its now-unprotected branch, re-read both to prove absence, and append the immutable cleanup event. The permanent receipt authority remains protected. Commit `datarim/delivery/TUNE-0585.authorization-marker.json` separately; it binds the freeze commit, exact clean repository/base, and dirty-inventory digest but does not self-name.
7. Create the detached authorization receipt/signature over the already-existing marker commit/path/digest, compare-append/refetch it through the permanent receipt authority, and append an `implementation_authorized` event plus its detached `event-attestation` under `event-receipts/`. Commit those artifacts and the cleanup record as a separate signed authorization-event commit. The validator derives that containing commit; the first source/test implementation commit must descend from it.
8. Verify exact ordering `spec-pair → trust-provision → contract-base → freeze → authorization-marker → authorization-event`, all signatures/receipts/provider sequences and Git ancestry from `d27b15f`, a clean branch, current permanent-branch protection, and absence of every disposable provider resource before Task 2.

**Validation:** provider feasibility semantics pass, hosted append/rejection/resolve and cleanup are independently signed and replayable, every receipt validates against the pre-existing registry, `git verify-commit` passes for trust provision/contract base/freeze/marker/authorization-event, `git merge-base --is-ancestor d27b15f HEAD` passes, exact commit ordering is proven, permanent authority protection is current, init-task and expectations gates exit 0, and both subordinate reports end `SPEC READY: YES`.

**Verifies:** V-AC-9.

### Task 2: Drive the core ledger contract RED

**Files:**

- Create: `tests/customer-delivery-gate.bats` `[to-be-created]`
- Create: `tests/fixtures/customer-delivery/` `[to-be-created]`

**Steps:**

1. Add fixtures for valid `none`, enabling, and bilingual-web ledgers plus provider-backed source and child manifests.
2. Add independent mutants for duplicate JSON keys/non-canonical bytes/floats/Unicode/key order/newline, every invalid primitive/nested record/array member/additional key, event-enum versus payload/handler set inequality, broken event/predecessor hashes, missing event attestation, wrong receipt subject, missing immutable anchor blob, anchored-head rollback/truncation/divergence, source omission/pagination/private-byte/HMAC/key-rotation/public-ID mutation, aggregate catch-all requirements, absent/stale/forged atomicity review, missing/dangling mappings, child omission/cycle/cross-project identity, and strict-mode reversion.
3. Add pre-work mutants for every capability class, omitted/duplicate/foreign requirement binding, missing/mismatched parent or evolution edge, request-branch requirement-set drift, missing/non-retrievable contract manifest, `Unbound`, em dash, mutable refs, absent freeze blob, freeze fixed-point/self-containing commit, missing/wrong authorization marker or external receipt, dirty/wrong base, non-descendant implementation, approval-required false with an approval event, approval-required true without block, rejected-to-applied, rejected-to-freeze, rejected without declined, review-fail without changes-required block, non-monotonic cursor, reused rejected request ID, unauthenticated decline, and crash-resume after rejection; add GREEN controls for exact requirement coverage, reuse/no-change, direct no-approval apply, approval, decline, review failure, and new-request-ID retry.
4. Add evidence/disposition mutants for fabricated/manual/hash-only receipts; wrong signer role/scope/namespace/audience; expired/revoked/downgraded registry; second-based/zero/out-of-range deadlines; process-group/grandchild timeout not reported as SIGTERM exit `143`; missing/forged raw wait status; SIGTERM-resistant forced-kill descendant leak; forged customer identity; vacuous RED; assertion mismatch; generic/404 live response; matrix-cell alias; missing each matrix cell; wrong deployed SHA; and accepted/returned/rejected/deferred/withdrawn semantics.
5. Add durability mutants for concurrent/divergent writers, duplicate retry, stale lock, short write/disk full, process death around rename/blob publication, fsync failure, anchor timeout-after-accept, unanchored recovery, anchor recursion, every forbidden supersession target/actor, duplicate target, shared replacement, branch, merge, cycle, older/inactive/already-superseded replacement, missing invalidation descendants, countermand selection by non-monotonic index, same-predecessor conflicts, unpaired reconciliation records, wrong conflict cardinality/shared predecessor/chosen membership, and unauthorized reconciliation.
6. Run the focused suite before creating the implementation and retain the expected missing-core assertion as raw development RED in `datarim/evidence/TUNE-0585/red/` `[to-be-created]`. It must fail at the intended assertion, not setup, but it is explicitly not a canonical runner attestation.

**Validation:** `bats tests/customer-delivery-gate.bats` exits non-zero at the intended missing-core assertion, not setup; evidence metadata says `development_only: true`.

**Verifies:** V-AC-1, V-AC-2, V-AC-4, V-AC-5, V-AC-7, V-AC-8, V-AC-10.

### Task 3: Implement the append-only ledger, safe adapters, and derived state

**Files:**

- Create: `scripts/customer-delivery-ledger.py` `[to-be-created]`
- Create: `dev-tools/check-customer-delivery.sh` `[to-be-created]`
- Create: `templates/customer-delivery-ledger.jsonl` `[to-be-created]`
- Create: `templates/customer-delivery-project.json` `[to-be-created]`
- Create: `datarim/delivery/TUNE-0585.jsonl` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/provider-integration.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/migration-input.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/source-snapshot.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/migration-plan.json` `[to-be-created]`
- Create: `config/customer-delivery-event-v1.schema.json` `[to-be-created]`
- Create: `config/customer-delivery-receipt-v1.schema.json` `[to-be-created]`
- Create: `config/customer-delivery-trust-catalog-v1.schema.json` `[to-be-created]`
- Create: `config/customer-delivery-project-v1.schema.json` `[to-be-created]`
- Create: `config/customer-delivery-migration-v1.schema.json` `[to-be-created]`
- Modify: `tests/customer-delivery-gate.bats`

**Steps:**

1. Transcribe the PRD's complete closed event, receipt/signature, trust-catalog/consumer-registry/project-registration, and migration schemas into the five executable schema files. Every object uses exact required keys and `additionalProperties:false`; every scalar, nullable, array member, nested record, enum, subject binding, and detached signature envelope is typed. Implement duplicate-key-rejecting JSONL/JSON parsing, exact event-index/genesis/integer-only UTF-8 canonicalization/test vectors, event/predecessor hashing, unique IDs, paired conflict reconciliation, supersession/observation tables, and set-equality tests across normative event/receipt enums, schemas, transition handlers, and documentation examples. Add owner-aware locking, durable fsync/atomic replacement/blob publication, idempotent retry, recoverable unanchored state, and unknown-schema/event/receipt fail-closed behavior.
2. Implement lane classification and immutable project-registry `canon_epoch`; strict adoption is monotonic.
3. Resolve private authoritative source/child manifests and public monotonic head anchors through governance-signed provider registrations. Enforce algorithm/key-or-issuer/subject/audience/namespace/role/scope/validity/revocation/verifier-digest and no-downgrade rules. Every accepted event must resolve and verify its detached `event-attestation` against the exact event preimage/hash and current registry revision. Invoke adapters with argv and `shell=False`, a fixed cwd, allowlisted environment, executable digest, integer-minute deadline, output cap, authentication metadata, and strict result schema; deadline expiry sends SIGTERM to the process group and returns the normalized exit-143 record.
4. Validate source exhaustion without printing verbatim/native IDs, exact HMAC capture/key rotation, exact-graph atomicity review, typed atomic ACs, parent identity, acyclic children, capability pins, freeze blob, authorization marker, immutable blob retrieval, anchored event count/head, and Git ancestry.
5. Derive `not_started`, `in_progress`, `customer_review`, `rework_required`, `blocked`, or `complete`; customer-visible requirements require accepted/withdrawn semantics, while enabling requirements require project-authority `verified` and never satisfy their parent.
6. Expose `init`, `append`, `validate --stage`, `derive`, and `migrate --plan|--apply` with the exact PRD arguments, including registry, signer, receipt-output, epoch, compatibility, and removal inputs. The shell wrapper maps contract findings to 1, usage/integrity to 2, and required-provider failure to 3.
7. Make every focused mutant RED and valid control GREEN.
8. Run real reference-provider integration against a temporary bare Git remote configured to reject non-fast-forward/deletion, real `ssh-keygen -Y` signatures/scoped allowed signers, a private HMAC source store, immutable blob append/resolve/replay, timeout-after-accept recovery, and read-only resolution of the existing protected `v2.66.2` remote tag. Fixture-only tests cannot clear provider feasibility.
9. Exercise the implemented `git-protected-ref-v1` adapter against a new disposable branch and disposable GitHub ruleset in `Arcanada-one/datarim`: create an exact-name branch from the reviewed test commit; create a ruleset targeting only that branch with deletion and non-fast-forward protection; publish and append through the adapter; prove non-fast-forward and deletion are rejected; resolve through the adapter in a clean temporary repository; and re-download/recompute the committed immutable ledger blob, Git OID, event count, and event head. Retain redacted raw provider bytes. First commit signed `datarim/evidence/TUNE-0585/provider-integration.json` with cleanup state `pending`. Only after that proof commit verifies, delete the disposable ruleset, delete the now-unprotected branch, prove both absent, append the second cleanup record to `datarim/evidence/TUNE-0585/provider-cleanup.jsonl`, and commit that cleanup separately with a valid signature. Never use the permanent receipt ref for a destructive test; use it only for compare-appended/refetched event receipts.
10. Create closed `datarim/evidence/TUNE-0585/migration-input.json` and signed `source-snapshot.json`, then create immutable `migration-plan.json` with the exact `migrate --plan --mode genesis` CLI, passing locally resolved committed bootstrap/input/snapshot/registry, exact authorization-event commit, null epoch/compatibility/removal inputs, bootstrap-pinned time, event signer, and receipt output. Every plan item contains the full canonical event, attestation ID, and complete unsigned receipt template with deterministic issued time/idempotency key; concatenation exactly reconstructs planned ledger bytes. Verify every input/output digest, then run the exact `migrate --apply` CLI with plan digest, input, source snapshot, registry, signer, receipt output, and ledger output. Apply uses the non-common provider-native request/result to reserve stable sequences and public compare tokens by idempotency key, fills only provider sequence, signs, compare-appends/refetches each event receipt, and advances exact recovery phases whose receipt IDs/times/idempotency keys are plan-derived. Failure after receipt publication leaves immutable `pending-orphan` receipts; they cannot pass a stage, recovery queries both reservations and receipts by deterministic keys, and an identical retry binds them after install. Re-run plan/apply to prove byte-identical/idempotent plan, ledger, native reservation result/signature, receipt, and recovery transitions; independently verify every field/digest against freeze/authorization and derive `genesis_unanchored`. Validate with `dev-tools/check-customer-delivery.sh --task TUNE-0585 --stage plan --root . --format json`. This conversion must complete before Task 4 records canonical evidence.

**Validation:** `bats tests/customer-delivery-gate.bats`; `python3 -m py_compile scripts/customer-delivery-ledger.py`; `dev-tools/check-customer-delivery.sh --task TUNE-0585 --stage plan --root . --format json`.

**Verifies:** V-AC-1, V-AC-2, V-AC-5, V-AC-7, V-AC-8, V-AC-10.

### Task 4: Implement runner-produced RED/GREEN and live evidence

**Files:**

- Modify: `scripts/customer-delivery-ledger.py`
- Modify: `tests/customer-delivery-gate.bats`
- Create: `tests/customer-delivery-evidence-runner.bats` `[to-be-created]`

**Steps:**

1. Add `run-evidence` using argv-only subprocess execution, integer-minute deadlines/output caps, process-group SIGTERM with normalized deadline exit `143`, raw wait/forced-kill/no-surviving-descendant observation bound in the signed receipt, repository/tree capture, stdout/stderr digests, retained paths, and a signature profile whose trust root is pinned in the consumer registry; reject digest-only receipts.
2. Require a mutation file/diff plus exact failing assertion for RED and restore-clean proof before GREEN. Reject setup/wrapper/unrelated failure and identical RED/GREEN receipts.
3. Add `record-deployment` and `record-visual` ingestion for authenticated external receipts; independently validate deployed/source provenance, live HTTP/DOM predicates, image format/dimensions/digest, effective locale/theme/viewport, and non-aliased cells.
4. Keep customer disposition as an independently resolved authority-signed record bound to requirement and deployed SHA. The runner and adapters cannot create acceptance.
5. After the runner is GREEN, break each load-bearing TUNE-0585 boundary with a present-day controlled mutation, capture signed canonical RED, restore clean bytes, capture signed GREEN, and append the receipts. Never relabel Task 2 output as canonical.

**Validation:** `bats tests/customer-delivery-evidence-runner.bats tests/customer-delivery-gate.bats`.

**Verifies:** V-AC-4, V-AC-8.

### Task 5: Implement deterministic migration and compatibility

**Files:**

- Create: `tests/customer-delivery-migration.bats` `[to-be-created]`
- Modify: `scripts/customer-delivery-ledger.py`
- Modify: `templates/customer-delivery-project.json`

**Steps:**

1. RED-test the exact `migrate --plan --mode legacy-v0` and `migrate --apply` wire formats for genuine init-task/append-log import, closed source-snapshot/migration-input/plan/recovery/CAS schemas, signed exhaustion and pagination, retroactive Overview recovery, legacy evidence text, no ambient clock/unregistered network access, source/input/registry drift, deterministic byte replay, stable receipt-sequence reservation under concurrent append/retry, remote-published/local-missing recovery, invalid recovery transition/signature, existing identical/non-identical targets, receipt partial failure, sibling-temp/fsync/rename failure, anchor-before-registry-CAS ordering, timeout-after-anchor recovery, exact CAS owner/request/result/expected sequence+digest, monotonic adoption, and dual-read sunset.
2. Import genuine bytes/digests as source events; mark agent-authored retroactive seeds `legacy_unverified_source` and implementation/test/deploy prose `legacy_claim_imported`.
3. Ensure neither legacy class satisfies source, pre-work, RED/GREEN, live, visual, or customer-disposition coverage.
4. Require an exact release/tag-object/commit/ledger/receipt `canon_epoch`, name one compatibility release and removal version in the immutable migration plan, publish and refetch every event attestation before target installation, anchor/resolve the new ledger before the registry owner's argv-only compare-and-swap, and fail closed after the removal version or on any strict-mode reversion. A crash after anchor resumes from resolved anchor state and never remigrates or duplicates receipts.
5. Re-run focused migration and core suites GREEN.

**Validation:** `bats tests/customer-delivery-migration.bats tests/customer-delivery-gate.bats`.

**Verifies:** V-AC-7.

### Task 6: Wire pre-work capture and review-to-evolution

**Files:**

- Create: `skills/customer-delivery/SKILL.md` `[to-be-created]`
- Modify: `skills/init-task-persistence/SKILL.md`
- Modify: `skills/expectations-checklist/SKILL.md`
- Modify: `skills/evolution/SKILL.md`
- Modify: `skills/evolution/class-ab-gate.md`
- Modify: `commands/dr-init.md`
- Modify: `commands/dr-prd.md`
- Modify: `commands/dr-plan.md`
- Modify: `commands/dr-design.md`
- Modify: `templates/prd-template.md`
- Create: `tests/customer-delivery-command-contract.bats` `[to-be-created]`

**Steps:**

1. Add command-contract RED tests for L1, L2, review source-kind, atomization, typed surface blueprints, registry-derived evolution ownership, every durable evolution transition/resume cursor, freeze, and authorization.
2. Classify every task at init. Armed lanes capture provider-backed source; `none` records a reason and is rejected for customer/visitor intent.
3. Remove false `verbatim` semantics from skipped-init recovery: agent summaries remain unverified legacy source.
4. Require PRD atomization and typed production predicates for armed work regardless of nominal complexity; route L1/L2 through the minimal required pre-work substage.
5. Freeze role, skill, blueprint, constraint, policy, success criterion, source-derived evolution disposition, and target authorization before `/dr-do`.
6. Make `/dr-plan` invoke the registry-derived architect/skill-creator pre-work evolution state machine for reversible task-scoped created/revised artifacts and success criteria; preserve the Class B hard gate, authenticated approval/rejection, exact before/after digests, blocked state, crash-safe resume cursor, review, and deterministic refreeze.
7. Keep expectations as a generated compatibility view and prohibit em dash/Unbound closure.

**Validation:** `bats tests/customer-delivery-command-contract.bats`; expectations/init-task gates for TUNE-0585.

**Verifies:** V-AC-1, V-AC-2, V-AC-3, V-AC-6.

### Task 7: Wire implementation, QA, live matrix, and closure

**Files:**

- Modify: `commands/dr-do.md`
- Modify: `commands/dr-qa.md`
- Modify: `commands/dr-compliance.md`
- Modify: `commands/dr-archive.md`
- Modify: `commands/dr-auto.md`
- Modify: `commands/dr-status.md`
- Modify: `skills/playwright-qa/SKILL.md`
- Modify: `skills/reflecting/SKILL.md`
- Modify: `templates/archive-template.md`
- Modify: `tests/customer-delivery-command-contract.bats`

**Steps:**

1. Require clean authorization and runner-produced RED before armed source implementation; free-form evidence markers remain commentary only.
2. Make QA validate the actual production blueprint. `bilingual-web-v1` requires RU/EN × mobile/desktop × light/dark, semantic DOM assertions, exact deployed SHA, and all retained screenshots; missing tooling blocks.
3. Make compliance reject artifact-only, tool-only, local-only, generic-page, incomplete-matrix, and non-accepted closure.
4. Route returned/rejected to pre-work evolution and rework; deferred to blocked; authenticated withdrawn out of the denominator; accepted to complete only after all evidence passes.
5. Resolve reflection/evolution rejection-routing contradictions and require an evolution disposition for every review item before remediation.
6. Make archive require derived complete; status and auto consume exact missing IDs/state rather than task prose.

**Validation:** `bats tests/customer-delivery-command-contract.bats tests/customer-delivery-gate.bats tests/customer-delivery-evidence-runner.bats`.

**Verifies:** V-AC-3, V-AC-4, V-AC-5, V-AC-6.

### Task 8: Close quick, content, replay, and future-command bypasses

**Files:**

- Modify: `commands/dr-quick.md`
- Modify: `commands/dr-write.md`
- Modify: `commands/dr-edit.md`
- Modify: `commands/dr-publish.md`
- Modify: `commands/dr-next.md`
- Modify: `commands/dr-orchestrate.md`
- Modify: `CLAUDE.md`
- Modify: `tests/customer-delivery-command-contract.bats`
- Modify: `tests/test-command-doc-coverage.bats`

**Steps:**

1. Add capability metadata/routing contract for every command that creates, implements, reviews, publishes, advances, or closes a task.
2. Make `/dr-quick` classify before edits; armed customer-visible work follows the minimal hard pipeline rather than bypassing it.
3. Make content commands preserve customer sources and distinguish prepared artifacts from public delivery. Keep external publication operator-gated.
4. Make replay/orchestration consume the ledger-derived next gate.
5. Add discovery tests that fail when any present or future advancing command lacks an explicit customer-delivery behavior.

**Validation:** `bats tests/customer-delivery-command-contract.bats tests/test-command-doc-coverage.bats`.

**Verifies:** V-AC-6.

### Task 9: Publish the framework contract and validate all surfaces

**Files:**

- Create: `documentation/reference/customer-delivery-canon.md` `[to-be-created]`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `CHANGELOG.md`
- Modify: `VERSION`
- Modify: `datarim/tasks.md`
- Modify: `datarim/activeContext.md`

**Steps:**

1. Document schema, event lifecycle, provider/runner trust boundary, surface blueprints, derived state, migration, failure codes, and adoption recipe.
2. Add selective-loading/router entries without duplicating the canonical skill.
3. Run focused suites, all Bats suites, spec lint, documentation/reference checks, English-only checks, and `./validate.sh`.
4. Before review, append all final canonical RED/GREEN/evidence and project-authority `enabling_disposition`, derive TUNE-0585 as `genesis_unanchored`/enabling-verified without claiming customer acceptance or parent delivery for `TALO-0001/C-REQ-DELIVERY-CANON`, commit every tracked byte, and freeze the candidate commit/tree/ledger blob/head/count/evidence-manifest digest.
5. Run subordinate specification compliance on that exact frozen candidate, then an independent subordinate exact-head quality review with the registered quality-reviewer role/key. Fix every blocking finding before freezing a new candidate. For a passing candidate, write the signed quality receipt only to the protected external receipt authority through compare-and-append. The receipt binds exact commit/tree/ledger/evidence/finding digests and remains outside the candidate branch and ledger, so the reviewed head cannot self-invalidate. Refetch and verify its bytes, registry sequence, role, namespace, and scope independently.
6. Push the unchanged reviewed feature head, open a protected PR, and require exact-head CI for that same commit. Do not append local review metadata afterward and do not self-merge unless normal repository authority explicitly permits it. The merge record must bind reviewed PR head to merged commit and prove identical tree/ledger blob; otherwise re-run exact-head review on the merged head before release.
7. The registry-named release authority uses its distinct key in two non-interchangeable validations: Git's required namespace `git` for the embedded SSH tag signature, and namespace `datarim-release-v1` for a separate closed `release-tag` receipt carried in the annotation. That receipt binds release version, reviewed PR head, merged commit/tree, ledger path/blob OID/byte length/event count/head, quality-receipt locator/digest, current release-ruleset ID/digest, and verifier profile/version/digest; it cannot self-name the eventual tag object. From a new empty repository, fetch only that tag and a fresh current host-rules response; run `git verify-tag` against the `git` namespace and separately verify the release receipt, verify current rules still target `refs/tags/v*` with deletion/update/non-fast-forward and no bypass, resolve full tag-object and peeled-commit OIDs, extract the ledger blob, recompute every bound value, refetch/verify the external quality receipt, and run the release-stage validator from the tagged tree over the `(ledger, quality receipt, release-tag receipt, tag object, current rules response)` tuple. A bad immutable tag is retained and superseded only by a new authorized release; it is never moved or deleted.
8. After tag/receipt/current-rules verification, construct Datarim consumer-registry sequence `n+1` with predecessor digest/sequence from the genesis registry and non-null `canon_epoch` binding release version, full tag object, peeled commit, ledger blob/head, and anchor receipt. Governance signs it, the registry owner publishes it through the exact `registry-cas` request, and a clean resolver refetches/verifies the authenticated result and immutable successor bytes. Only this external successor makes the release canonical and permits the universal canon complete verdict; it is never appended to its subject ledger and no unplanned next Git release/commit is required. A downstream consumer registry records the receipt locator/digest, tag object, peeled commit, ledger blob/head/count, and release version when it adopts the canon. Talomnia must first register and probe its own dedicated `git-protected-ref-v1` append branch before strict mode.

**Pre-merge validation:** `bats tests/*.bats`; `bats dev-tools/tests/*.bats`; `./dev-tools/dr-spec-lint.sh --task TUNE-0585 --root . --stage verify --format text`; `./validate.sh`; external quality-receipt refetch/verification; exact-head CI for the unchanged reviewed PR head.

**Post-merge release validation:** initialize an empty resolver; fetch only `refs/tags/v$(tr -d '\n' < VERSION)`; check out the fetched tag detached; run `git verify-tag` with the release authority allowed for namespace `git`; separately extract and verify the closed annotation receipt under `datarim-release-v1`; resolve the full tag object, peeled commit, tree, and `datarim/delivery/TUNE-0585.jsonl` blob OIDs; extract and rehash the ledger; refetch the external quality receipt and current release-ruleset response; validate signer/schema/registry/full OIDs/byte length/event count/head/evidence digest/current rules; invoke the validator from the checked-out tagged tree as `"$resolver/dev-tools/check-customer-delivery.sh" --task TUNE-0585 --stage release --root "$resolver" --quality-receipt <resolved-receipt> --anchor-receipt <resolved-tag-annotation> --format json`; then publish/refetch the signed registry successor with exact predecessor and `canon_epoch` through `registry-cas`. Never invoke the feature-worktree validator for tagged bytes. All commands and successor verification must exit 0 before V-AC-9 or canonical completion passes.

**Verifies:** V-AC-1, V-AC-2, V-AC-3, V-AC-4, V-AC-5, V-AC-6, V-AC-7, V-AC-8, V-AC-9, V-AC-10.

## Rollback and preservation

- Every ledger correction is a superseding event; never rewrite evidence history.
- Framework changes are isolated on `feat/TUNE-0585-customer-delivery-canon`; rollback is a normal revert PR, not history rewriting.
- A failed adapter, live probe, matrix cell, or customer disposition leaves the exact requirement blocked with retained evidence.
- Talomnia adoption begins only after the universal release is exact-head green. It uses separate isolated worktrees and does not mutate `talomnia-knowledge` PR #44.

## Out of Scope

- Talomnia registration, requirement import, site implementation, deployment, screenshots, customer acceptance, and PR #44 mutation are downstream.
- No ecosystem-site sync is required for this framework-only change. Public Datarim `README.md`, reference documentation, changelog, and release metadata are in scope and validated here.
- Creating a dedicated Talomnia protected ledger branch/ruleset is downstream adoption work after the released provider exists.

## Test Plan

- Unit/contract: canonical hashes, schema/events, private-source digest checks, atomicity review, typed ACs, state derivation, disposition semantics.
- Integration: Git repositories for ancestry/protected-ref resolution, synthetic SSH signatures, constrained adapter processes, concurrent/crash writer recovery.
- Mutation: every omission, capability class, RED/GREEN assertion, deployment mismatch, matrix cell, forged trust receipt, rollback/truncation, bypass command, and legacy non-coverage boundary.
- Full regression: all root and `dev-tools/` Bats suites, spec graph, English/history/security gates, shellcheck, Python compile/Bandit when available, and `validate.sh`.
- Exact-head: subordinate spec review before implementation; spec compliance then quality review for each implementation task; final adversarial S11 and exact-head quality review before PR readiness.

## Validation Checklist

| Deliverable | Acceptance proof | V-AC |
|---|---|---|
| Closed-world source and atomic mapping | provider omission/private HMAC mutation/aggregate/stale-review mutants RED; authenticated exact-graph control GREEN | V-AC-1 |
| Pre-work ordering | spec/freeze/auth commits plus capability/base/ancestry mutants | V-AC-2 |
| Review evolution | source-kind and missing/post-hoc artifact mutants; `/dr-plan` resume control | V-AC-3 |
| Live delivery | signed RED/GREEN, deploy, semantic probe, eight non-aliased matrix cells, authenticated disposition | V-AC-4 |
| Derived epic state | omitted/cyclic/cross-project child and narrated-complete mutants | V-AC-5 |
| Universal routing | discovered command capabilities; L1/L2/quick/content/replay/new-command mutants | V-AC-6 |
| Migration | exact epoch, one-release sunset, monotonic strict adoption, legacy non-coverage | V-AC-7 |
| Trust boundary | no-shell/argv/env/path/time/output; signer role/scope/validity/revocation/downgrade; signature/customer forgery; independent receipt verification | V-AC-8 |
| Genesis | six ordered pre-code commits, development-only raw RED, present-day signed mutation, protected-ref epoch | V-AC-9 |
| Durability | canonical bytes, immutable blob retrieval, concurrency/retry/stale-lock/crash/disk/anchor/rollback/supersession mutants | V-AC-10 |

### Artifact validation matrix

Every modified or new artifact has a direct check; shared suite rows do not substitute for the named check.

| Artifact | Direct validation |
|---|---|
| `datarim/prd/PRD-TUNE-0585.md` | spec lint resolves D-REQ/V-AC graph at exact blueprint revision |
| `datarim/plans/TUNE-0585-plan.md` | plan-stage spec lint, path report, and exact-blob spec review |
| `datarim/tasks/TUNE-0585-task-description.md` | task schema/init-task presence and AC cross-check |
| `datarim/tasks/TUNE-0585-expectations.md` | expectations validator and wish-to-V-AC graph |
| `datarim/delivery/TUNE-0585.bootstrap.json` | bootstrap schema, private commitments, exact spec/freeze/auth ordering |
| `datarim/delivery/TUNE-0585.contract-manifest.json` | exact active-requirement denominator, parent/evolution edges, six non-empty capability classes, locator/digest |
| `datarim/delivery/TUNE-0585.authorization-marker.json` | repository/base/dirty-inventory marker schema and signed freeze ancestry |
| `datarim/delivery/TUNE-0585.jsonl` | canonical parser, hash chain, genesis conversion, derive report |
| `datarim/evidence/TUNE-0585/spec-review.json` | signature/trust scope, exact commit, verdict schema |
| `datarim/evidence/TUNE-0585/spec-review.json.sig` | detached signature envelope and spec-reviewer namespace verification |
| `datarim/evidence/TUNE-0585/authorization-receipt.json` | closed authorization subject bound to freeze and marker commits |
| `datarim/evidence/TUNE-0585/authorization-receipt.json.sig` | detached authorization signature and registry/provider-sequence verification |
| `datarim/evidence/TUNE-0585/provider-feasibility.json` | replay argv/output digests and signed overall PASS |
| `datarim/evidence/TUNE-0585/provider-raw/` | manifest proves every redacted raw response byte is retained and digest-bound |
| `datarim/evidence/TUNE-0585/provider-integration.json` | signed implemented-adapter hosted fast-forward/rejection/resolve proof with cleanup pending |
| `datarim/evidence/TUNE-0585/provider-cleanup.jsonl` | two-phase cleanup schema, signed ancestry, exact resource absence readback, idempotent recovery |
| `datarim/evidence/TUNE-0585/event-receipts/` | manifest, detached signatures, permanent-authority refetch, and event-set equality |
| `datarim/evidence/TUNE-0585/migration-recovery.json` | pending-orphan/bound receipt state, install boundary, and idempotent recovery checks |
| `datarim/evidence/TUNE-0585/migration-input.json` | closed schema, source/freeze/authorization digest cross-check, and deterministic replay |
| `datarim/evidence/TUNE-0585/source-snapshot.json` | source-provider signature, exhaustion/count/order, immutable anchor, and HMAC replay |
| `datarim/evidence/TUNE-0585/migration-plan.json` | immutable plan input/output digests, deterministic replay, plan/apply equality |
| `datarim/evidence/TUNE-0585/red/` | raw development RED manifest proves intended assertion failure and `development_only: true` |
| `config/customer-delivery-trust-catalog.json` | closed catalog schema, canonical digest, governance root/profile-floor checks |
| `config/customer-delivery-trust-catalog.json.sig` | detached namespace/signature verification against pinned genesis root |
| `config/customer-delivery-datarim-registry.json` | closed consumer schema, catalog link, roles/providers/scopes/revocation/adoption checks |
| `config/customer-delivery-datarim-registry.json.sig` | detached consumer-registry signature and non-self-signing verification |
| `config/customer-delivery-allowed-signers` | exact derived-view digest, no extra principals/namespaces, distinct role keys |
| `config/customer-delivery-bootstrap-provider-v1.json` | pinned existing executable/version/digest/script/argv/env/cwd closed schema and replay |
| `config/customer-delivery-bootstrap-provider-v1.json.sig` | governance fingerprint, detached namespace signature, and exact registration digest |
| `config/customer-delivery-provider-registrations/` | non-self-referential payloads, detached governance signatures, separate registry payload/signature locator/digest equality |
| `config/customer-delivery-event-v1.schema.json` | enum/schema/transition/documentation set equality plus canonical vectors |
| `config/customer-delivery-receipt-v1.schema.json` | exact common/signature/subject schema, role/namespace binding, and additional-key mutants |
| `config/customer-delivery-trust-catalog-v1.schema.json` | exact catalog/profile/role/provider/consumer nested record schema and no-downgrade mutants |
| `config/customer-delivery-project-v1.schema.json` | exact registration/epoch/profile/authority schema and monotonic-adoption mutants |
| `config/customer-delivery-migration-v1.schema.json` | exact snapshot/input/plan schemas, deterministic vectors, and unknown-key mutants |
| `tests/fixtures/customer-delivery/` | fixture manifest proves every valid/mutant case is consumed |
| `tests/customer-delivery-gate.bats` | focused RED/GREEN core contract and every independent mutant |
| `tests/customer-delivery-evidence-runner.bats` | real runner receipt/signature/attribution/live-ingest cases |
| `tests/customer-delivery-migration.bats` | epoch/sunset/legacy/non-fabrication cases |
| `tests/customer-delivery-command-contract.bats` | command capability discovery and phase wiring |
| `scripts/customer-delivery-ledger.py` | focused Bats, `py_compile`, Bandit, method-size/self-review |
| `dev-tools/check-customer-delivery.sh` | wrapper exit mapping, child-attribution mutation, ShellCheck |
| `templates/customer-delivery-ledger.jsonl` | template is non-passing, English, canonical event example lint |
| `templates/customer-delivery-project.json` | registration schema/trust roles/profile fixtures |
| `skills/customer-delivery/SKILL.md` | command references, history/English/security policy gates |
| `skills/init-task-persistence/SKILL.md` | retroactive-verbatim negative contract test |
| `skills/expectations-checklist/SKILL.md` | armed-lane compatibility-view/non-authority contract test |
| `skills/evolution/SKILL.md` | durable pre-work evolution state-machine clauses |
| `skills/evolution/class-ab-gate.md` | approval/rejection/resume/refreeze routing test |
| `skills/playwright-qa/SKILL.md` | production blueprint and eight-cell hard-floor contract tests |
| `skills/reflecting/SKILL.md` | review disposition/rework routing consistency test |
| `commands/dr-init.md` | classification/source capture/L1-L4 contract cases |
| `commands/dr-prd.md` | atomization/typed AC/atomicity-review contract cases |
| `commands/dr-plan.md` | evolution/freeze/authorization/provider-probe contract cases |
| `commands/dr-design.md` | design capability pin and no-bypass contract case |
| `commands/dr-do.md` | authorization plus runner RED-before-GREEN contract cases |
| `commands/dr-qa.md` | exact deploy/live/matrix/disposition hard gate cases |
| `commands/dr-compliance.md` | artifact-only and non-accepted closure negatives |
| `commands/dr-archive.md` | derived-complete-only archive routing case |
| `commands/dr-auto.md` | exact missing-ID reversible-next-action case |
| `commands/dr-status.md` | derived-state rendering and narrated-state rejection case |
| `commands/dr-quick.md` | customer-visible fast-lane bypass negative |
| `commands/dr-write.md` | source preservation and draft-not-delivery case |
| `commands/dr-edit.md` | review source-kind and draft-not-delivery case |
| `commands/dr-publish.md` | operator-gated publication and no-tool-only closure case |
| `commands/dr-next.md` | replay from derived next gate case |
| `commands/dr-orchestrate.md` | orchestration cannot bypass armed gate case |
| `templates/prd-template.md` | source-to-atomic typed graph template lint |
| `templates/archive-template.md` | derived coverage/live matrix/disposition rendering lint |
| `tests/test-command-doc-coverage.bats` | new advancing-command metadata discovery regression |
| `documentation/reference/customer-delivery-canon.md` | doc links, examples, English/security/runtime probes |
| `CLAUDE.md` | selective-loading route and universal hard-floor contract test |
| `README.md` | public feature/adoption link and doc-reference check |
| `CHANGELOG.md` | version entry, public-surface hygiene, task-ID gate rules |
| `VERSION` | version consistency checks across shipped/runtime surfaces |
| `datarim/tasks.md` | canonical in-progress/completed transition schema |
| `datarim/activeContext.md` | exact tasks mirror check |

## Next Steps

1. Obtain `SPEC READY: YES` on the exact amended spec/plan commit.
2. Commit trust provision, contract base, genesis freeze, authorization marker, and authorization event separately after the concrete provider feasibility probe.
3. Execute Tasks 2-9 continuously through subordinate implementer → spec review → quality review cycles.
4. Land through the protected PR path; then register and reconcile Talomnia in separate isolated worktrees.

## Path validation

All existing edit/validation targets above must resolve in the exact-base worktree. Every absent path is explicitly marked `[to-be-created]`; no deprecated target is allowed. Run the plan-path validator again after any path revision and before `/dr-do`.

PATH VALIDATION

- checked: 77 unique artifact/edit/validation path references, including this plan;
- present: 35 paths (34 exact-base targets plus this plan);
- expected new: 42 paths, each explicitly marked `[to-be-created]`;
- unexpected missing: 0;
- deprecated edit targets: 0 (the only marker hits describe retired concepts inside live current files, not retired target paths);
- runtime-body probe: clean; the plan does not prescribe task-ID provenance in shipped `commands/`, `skills/`, `templates/`, or `CLAUDE.md` bodies.
