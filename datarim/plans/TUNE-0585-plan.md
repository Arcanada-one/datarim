---
task_id: TUNE-0585
artifact: plan
status: approved
created: 2026-08-22
prd: datarim/prd/PRD-TUNE-0585.md
blueprint_revision: f834877498cfffdd12bca77c510bcaecd9c61f0c
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

Genesis uses two commits because the framework cannot self-attest before its runner exists. First commit a bootstrap freeze record after spec approval; then commit a distinct authorization marker over the clean implementation base. Implementation begins only in a descendant of the authorization commit. Raw TDD proves development sequencing but is not canonical evidence. After the runner exists, a present-day mutation/restoration supplies signed canonical RED/GREEN, and the merge to the selected protected ref becomes the monotonic `canon_epoch`.

## Implementation Steps

### Task 1: Close specification and bootstrap dogfood provenance

**Files:**

- Modify: `datarim/prd/PRD-TUNE-0585.md`
- Modify: `datarim/tasks/TUNE-0585-task-description.md`
- Modify: `datarim/tasks/TUNE-0585-expectations.md`
- Create: `datarim/delivery/TUNE-0585.bootstrap.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/spec-review.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/provider-feasibility.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/provider-cleanup.jsonl` `[to-be-created]`
- Create: `datarim/delivery/TUNE-0585.authorization.json` `[to-be-created]`
- Create: `config/customer-delivery-trust-catalog.json` `[to-be-created]`
- Create: `config/customer-delivery-trust-catalog.json.sig` `[to-be-created]`
- Create: `config/customer-delivery-datarim-registry.json` `[to-be-created]`
- Create: `config/customer-delivery-datarim-registry.json.sig` `[to-be-created]`
- Create: `config/customer-delivery-allowed-signers` `[to-be-created]`

**Steps:**

1. Provision distinct non-repository role keys and governance-signed assignment records for the spec reviewer and the later quality reviewer/runner/providers without changing implementation source. Obtain a subordinate exact-blob review of the amended spec; materialize its canonical receipt, bind the exact PRD/plan commit and finding digest, sign it with the assigned spec-reviewer key/namespace, and retain both receipt and governance assignment for the freeze.
2. If the verdict is NO, revise the spec, commit it, and repeat exact-blob review. Do not edit implementation source before YES.
3. Before any implementation source or RED test is created, complete a hard-deadline ≤60-second feasibility probe of the concrete genesis and ongoing profiles. The replay below covers signer behavior and immutable-tag resolution; the same report must also contain a disposable hosted append/resolve probe that proves current admin/write/read credential scope. Create a uniquely named temporary branch from the reviewed spec head, create/read back a GitHub ruleset targeting only that exact branch with `deletion` and `non_fast_forward` rules and no bypass actor, push a first commit containing a synthetic immutable ledger blob, and push one append-only fast-forward. Then issue an actual remote forced update with `git push --force-with-lease=<full-ref>:<known-remote-oid> origin <ancestor>:<full-ref>` and an actual remote deletion with `git push origin :<full-ref>`; both must reach GitHub and fail with the named ruleset/rule ID, not client fast-forward checks, auth, hooks, or malformed argv. Clone into a new empty repository and recompute the full branch commit OID, ledger Git blob OID, byte length, event count, and event head from fetched bytes. Record the ruleset creation/readback response and every exact Git/API argv, exit code, redacted output digest, start/end time, and attribution assertion. The disposable branch remains protected until Step 5 cleanup. Timeout or failed API/write/read/rejection/resolve blocks the freeze and all source work.

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

   Materialize `provider-feasibility.json` from the captured outputs with `apply_patch` before the freeze; the report is not implicit output of the replay. Validate it before commit with an inline duplicate-key-rejecting JSON reader that asserts the exact schema and semantics: `schema_version == 1`; every command exit is expected; release ruleset `16418778` is active, targets `refs/tags/v*`, has no bypass, and contains `deletion`, `non_fast_forward`, and `update`; default ruleset `15879567` is recorded ineligible; the disposable ruleset is active, exact-branch scoped, has no bypass, and contains `deletion` plus `non_fast_forward`; initial/fast-forward pushes pass; non-fast-forward/deletion pushes fail at the named remote-rule assertion; and the clean-clone resolved full commit/blob/event OIDs equal the published values. The 2026-08-22 read-only probe already confirmed SSH verification, API read, and immutable tag resolution: tag object `610466796fc34e196645d7c91d9f9fcf317c29d5` peels to commit `eb54e9cf881ca14f7a689b831598285f38561e89`; it did not substitute for this hosted write-scope probe.
4. Create the concrete schema-v1 framework trust catalog, Datarim consumer registry, derived allowed-signers view, and both detached governance signatures. Recompute the pinned genesis governance fingerprint, allowed-signers/catalog/registry digests, every signer fingerprint/scope/namespace/validity, verifier executable/version/digest, catalog→consumer chain, predecessor/adoption state, and signatures with the exact namespace-specific `ssh-keygen -Y verify`; prove no mutually exclusive authority role shares a key. Commit only public keys for `spec-reviewer`, `quality-reviewer`, `evidence-runner`, `project-verifier`, `source-provider`, `deployment-provider`, and `visual-provider`; their private keys remain outside Git. Then create the bootstrap freeze record with private operator-amendment source provenance, atomic framework requirements/review, `enabling-v1` pre-registration parent intent `TALO-0001/C-REQ-DELIVERY-CANON`, evolution disposition, all existing six capability classes, selected `git-immutable-tag-v1`, `git-protected-ref-v1`, and `git-ssh-v1` profiles, explicit migration time, and the reviewed PRD commit recorded by plan frontmatter. Include exact catalog/registry/report/review digests and commit freeze alone. Do not falsely select the current default branch as a monotonic append authority.
5. Resolve the signed freeze commit with `freeze_commit="$(git rev-parse HEAD)"` and verify its governance signature, exact identity/scope, and committed report/bootstrap/catalog/registry digests. Only then delete the disposable ruleset, delete the now-unprotected disposable branch, re-read both resources to prove absence, and append an immutable cleanup record to `datarim/evidence/TUNE-0585/provider-cleanup.jsonl`. In a second signed commit, add that cleanup record and `datarim/delivery/TUNE-0585.authorization.json`, which binds the exact clean Datarim base/repository/dirty-inventory digest and becomes the authorization marker. This two-phase order makes the probe durable before cleanup and cleanup durable before implementation. Do not claim a ledger anchor or canonical RED yet.
6. Verify spec → freeze → authorization are three ordered signed commits descending from exact base `d27b15f`; verify both report schemas and exact Git ancestry; branch is clean and no disposable provider resources remain before Task 2.

**Validation:** provider feasibility semantics pass, hosted append/rejection/resolve and cleanup are independently signed and replayable, `git verify-commit` passes for freeze and authorization, `git merge-base --is-ancestor d27b15f HEAD` passes, exact commit ordering is proven, init-task and expectations gates exit 0, and subordinate report ends `SPEC READY: YES`.

**Verifies:** V-AC-9.

### Task 2: Drive the core ledger contract RED

**Files:**

- Create: `tests/customer-delivery-gate.bats` `[to-be-created]`
- Create: `tests/fixtures/customer-delivery/` `[to-be-created]`

**Steps:**

1. Add fixtures for valid `none`, enabling, and bilingual-web ledgers plus provider-backed source and child manifests.
2. Add independent mutants for duplicate JSON keys/non-canonical bytes/floats/Unicode/key order/newline, broken event/predecessor hashes, missing immutable anchor blob, anchored-head rollback/truncation/divergence, source omission/pagination/private-byte/HMAC/key-rotation/public-ID mutation, aggregate catch-all requirements, absent/stale/forged atomicity review, missing/dangling mappings, child omission/cycle/cross-project identity, and strict-mode reversion.
3. Add pre-work mutants for every capability class, `Unbound`, em dash, mutable refs, absent freeze blob, missing/wrong authorization marker, dirty/wrong base, non-descendant implementation, rejected-to-applied, rejected-to-freeze, reused rejected request ID, unauthenticated decline, and crash-resume after rejection; add a GREEN new-request-ID retry control.
4. Add evidence/disposition mutants for fabricated/manual/hash-only receipts; wrong signer role/scope/namespace/audience; expired/revoked/downgraded registry; forged customer identity; vacuous RED; assertion mismatch; generic/404 live response; matrix-cell alias; missing each matrix cell; wrong deployed SHA; and accepted/returned/rejected/deferred/withdrawn semantics.
5. Add durability mutants for concurrent/divergent writers, duplicate retry, stale lock, short write/disk full, process death around rename/blob publication, fsync failure, anchor timeout-after-accept, unanchored recovery, anchor recursion, target-specific supersession, same-predecessor conflicts, and unauthorized supersession.
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
- Create: `datarim/evidence/TUNE-0585/migration-plan.json` `[to-be-created]`
- Create: `config/customer-delivery-event-v1.schema.json` `[to-be-created]`
- Modify: `tests/customer-delivery-gate.bats`

**Steps:**

1. Transcribe the PRD's complete closed schema-v1 envelope/reusable records/event payload table into the executable event schema. Implement duplicate-key-rejecting JSONL parsing, exact event-index/genesis/integer-only UTF-8 canonicalization/test vectors, event/predecessor hashing, unique IDs, target/actor/conflict reconciliation/supersession tables, and a set-equality test across normative event enum, payload schemas, transition handlers, and documentation examples. Add owner-aware locking, durable fsync/atomic replacement/blob publication, idempotent retry, recoverable unanchored state, and unknown-schema/event fail-closed behavior.
2. Implement lane classification and immutable project-registry `canon_epoch`; strict adoption is monotonic.
3. Resolve private authoritative source/child manifests and public monotonic head anchors through governance-signed provider registrations. Enforce algorithm/key-or-issuer/subject/audience/namespace/role/scope/validity/revocation/verifier-digest and no-downgrade rules. Invoke adapters with argv and `shell=False`, a fixed cwd, allowlisted environment, executable digest, timeout, output cap, authentication metadata, and strict result schema.
4. Validate source exhaustion without printing verbatim/native IDs, exact HMAC capture/key rotation, exact-graph atomicity review, typed atomic ACs, parent identity, acyclic children, capability pins, freeze blob, authorization marker, immutable blob retrieval, anchored event count/head, and Git ancestry.
5. Derive `not_started`, `in_progress`, `customer_review`, `rework_required`, `blocked`, or `complete`; customer-visible requirements require accepted/withdrawn semantics, while enabling requirements require project-authority `verified` and never satisfy their parent.
6. Expose `init`, `append`, `validate --stage`, `derive`, and `migrate --plan|--apply` with the exact PRD arguments. The shell wrapper maps contract findings to 1, usage/integrity to 2, and required-provider failure to 3.
7. Make every focused mutant RED and valid control GREEN.
8. Run real reference-provider integration against a temporary bare Git remote configured to reject non-fast-forward/deletion, real `ssh-keygen -Y` signatures/scoped allowed signers, a private HMAC source store, immutable blob append/resolve/replay, timeout-after-accept recovery, and read-only resolution of the existing protected `v2.66.2` remote tag. Fixture-only tests cannot clear provider feasibility.
9. Exercise the implemented `git-protected-ref-v1` adapter against a new disposable branch and disposable GitHub ruleset in `Arcanada-one/datarim`: create an exact-name branch from the reviewed test commit; create a ruleset targeting only that branch with deletion and non-fast-forward protection; publish and append through the adapter; prove non-fast-forward and deletion are rejected; resolve through the adapter in a clean temporary repository; and re-download/recompute the committed immutable ledger blob, Git OID, event count, and event head. First commit signed `datarim/evidence/TUNE-0585/provider-integration.json` with cleanup state `pending`. Only after that proof commit verifies, delete the disposable ruleset, delete the now-unprotected branch, prove both absent, append the second cleanup record to `datarim/evidence/TUNE-0585/provider-cleanup.jsonl`, and commit that cleanup separately with a valid signature. Never use the production ledger ref for this test.
10. Create immutable `datarim/evidence/TUNE-0585/migration-plan.json` with `migrate --plan --mode genesis`, passing the committed bootstrap, signed source snapshot, exact authorization commit, null epoch/compatibility/removal inputs, and bootstrap-pinned migration time. Verify the plan's input/output digests and then run `migrate --apply --plan datarim/evidence/TUNE-0585/migration-plan.json --plan-sha256 <verified-plan-digest> --output datarim/delivery/TUNE-0585.jsonl`. Re-run plan and apply to prove byte-identical/idempotent output; independently verify every field/digest against freeze/authorization and derive `genesis_unanchored`. Validate with `dev-tools/check-customer-delivery.sh --task TUNE-0585 --stage plan --root . --format json`. This conversion must complete before Task 4 records canonical evidence.

**Validation:** `bats tests/customer-delivery-gate.bats`; `python3 -m py_compile scripts/customer-delivery-ledger.py`; `dev-tools/check-customer-delivery.sh --task TUNE-0585 --stage plan --root . --format json`.

**Verifies:** V-AC-1, V-AC-2, V-AC-5, V-AC-7, V-AC-8, V-AC-10.

### Task 4: Implement runner-produced RED/GREEN and live evidence

**Files:**

- Modify: `scripts/customer-delivery-ledger.py`
- Modify: `tests/customer-delivery-gate.bats`
- Create: `tests/customer-delivery-evidence-runner.bats` `[to-be-created]`

**Steps:**

1. Add `run-evidence` using argv-only subprocess execution, timeout/output caps, repository/tree capture, exit code, stdout/stderr digests, retained paths, and a signature profile whose trust root is pinned in the consumer registry; reject digest-only receipts.
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

1. RED-test `migrate --plan --mode legacy-v0` and `migrate --apply` for exact genuine init-task/append-log import, signed source-snapshot exhaustion, provider pagination, retroactive Overview recovery, legacy evidence text, plan/input drift, deterministic replay, partial-failure recovery, monotonic adoption, and dual-read sunset.
2. Import genuine bytes/digests as source events; mark agent-authored retroactive seeds `legacy_unverified_source` and implementation/test/deploy prose `legacy_claim`.
3. Ensure neither legacy class satisfies source, pre-work, RED/GREEN, live, visual, or customer-disposition coverage.
4. Require an exact release/tag-object/commit/ledger/receipt `canon_epoch`, name one compatibility release and removal version in the immutable migration plan, anchor/resolve the new ledger before registry CAS, and fail closed after the removal version or on any strict-mode reversion.
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
7. A named release authority creates the protected signed annotated tag whose closed receipt annotation binds release version, reviewed PR head, merged commit/tree, ledger path/blob OID/byte length/event count/head, quality-receipt locator/digest, ruleset digest, and verifier identity. From a new empty repository, fetch only that tag, verify its signature against the registry's release/anchor authority and namespace, resolve full tag-object and peeled-commit OIDs, extract the ledger blob, recompute every bound value, refetch/verify the external quality receipt, and run the release-stage validator over the `(ledger, quality receipt, tag receipt)` tuple. A bad immutable tag is retained and superseded only by a new authorized release; it is never moved or deleted.
8. The verified external tag receipt is sufficient to establish this release's `canon_epoch` and report the universal canon complete; it is never appended to its subject ledger and no unplanned next release is required. A downstream consumer registry records the receipt locator/digest, tag object, peeled commit, ledger blob/head/count, and release version when it adopts the canon. Talomnia must first register and probe its own dedicated `git-protected-ref-v1` append branch before strict mode.

**Pre-merge validation:** `bats tests/*.bats`; `bats dev-tools/tests/*.bats`; `./dev-tools/dr-spec-lint.sh --task TUNE-0585 --root . --stage verify --format text`; `./validate.sh`; external quality-receipt refetch/verification; exact-head CI for the unchanged reviewed PR head.

**Post-merge release validation:** initialize an empty resolver; fetch only `refs/tags/v$(tr -d '\n' < VERSION)`; run `git verify-tag`; resolve the full tag object, peeled commit, tree, and `datarim/delivery/TUNE-0585.jsonl` blob OIDs; extract and rehash the ledger; refetch the external quality receipt; validate signer/schema/registry/full OIDs/byte length/event count/head/evidence digest; then run `dev-tools/check-customer-delivery.sh --task TUNE-0585 --stage release --root . --quality-receipt <resolved-receipt> --anchor-receipt <resolved-tag-annotation> --format json`. All commands must exit 0 on the merged/tagged objects before V-AC-9 or canonical completion passes.

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
| Genesis | three pre-code commits, development-only raw RED, present-day signed mutation, protected-ref epoch | V-AC-9 |
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
| `datarim/delivery/TUNE-0585.authorization.json` | repository/base/dirty-inventory marker schema and signed authorization ancestry |
| `datarim/delivery/TUNE-0585.jsonl` | canonical parser, hash chain, genesis conversion, derive report |
| `datarim/evidence/TUNE-0585/spec-review.json` | signature/trust scope, exact commit, verdict schema |
| `datarim/evidence/TUNE-0585/provider-feasibility.json` | replay argv/output digests and signed overall PASS |
| `datarim/evidence/TUNE-0585/provider-integration.json` | signed implemented-adapter hosted fast-forward/rejection/resolve proof with cleanup pending |
| `datarim/evidence/TUNE-0585/provider-cleanup.jsonl` | two-phase cleanup schema, signed ancestry, exact resource absence readback, idempotent recovery |
| `datarim/evidence/TUNE-0585/migration-plan.json` | immutable plan input/output digests, deterministic replay, plan/apply equality |
| `datarim/evidence/TUNE-0585/red/` | raw development RED manifest proves intended assertion failure and `development_only: true` |
| `config/customer-delivery-trust-catalog.json` | closed catalog schema, canonical digest, governance root/profile-floor checks |
| `config/customer-delivery-trust-catalog.json.sig` | detached namespace/signature verification against pinned genesis root |
| `config/customer-delivery-datarim-registry.json` | closed consumer schema, catalog link, roles/providers/scopes/revocation/adoption checks |
| `config/customer-delivery-datarim-registry.json.sig` | detached consumer-registry signature and non-self-signing verification |
| `config/customer-delivery-allowed-signers` | exact derived-view digest, no extra principals/namespaces, distinct role keys |
| `config/customer-delivery-event-v1.schema.json` | enum/schema/transition/documentation set equality plus canonical vectors |
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
2. Commit genesis freeze and authorization separately after the concrete provider feasibility probe.
3. Execute Tasks 2-9 continuously through subordinate implementer → spec review → quality review cycles.
4. Land through the protected PR path; then register and reconcile Talomnia in separate isolated worktrees.

## Path validation

All existing edit/validation targets above must resolve in the exact-base worktree. Every absent path is explicitly marked `[to-be-created]`; no deprecated target is allowed. Run the plan-path validator again after any path revision and before `/dr-do`.

PATH VALIDATION

- checked: 61 unique artifact/edit/validation path references, including this plan;
- present: 35 paths (34 exact-base targets plus this plan);
- expected new: 26 paths, each explicitly marked `[to-be-created]`;
- unexpected missing: 0;
- deprecated edit targets: 0 (the only marker hits describe retired concepts inside live current files, not retired target paths);
- runtime-body probe: clean; the plan does not prescribe task-ID provenance in shipped `commands/`, `skills/`, `templates/`, or `CLAUDE.md` bodies.
