---
task_id: TUNE-0585
artifact: plan
status: approved
created: 2026-08-22
prd: datarim/prd/PRD-TUNE-0585.md
exact_base: d27b15f390265fef1fc95c31a28677a9664acb98
spec_reviewed_commit: 931df32
---

# Universal Customer-Delivery Canon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `subagent-driven-development` to execute this plan task-by-task, with a specification check after each implementation task and an independent exact-head quality review before completion.

**Goal:** Ship a universal, fail-closed Datarim customer-delivery ledger that preserves authoritative customer remarks, enforces pre-work attribution and review-to-evolution, captures load-bearing evidence, derives task/epic state from closed-world coverage, and prevents user-facing completion from tools or tests alone.

**Architecture:** A standard-library Python core owns an append-only SHA-256 event ledger, constrained provider adapters, a runner-produced evidence receipt, phase validation, migration, and derived state. A thin shell gate exposes stable lifecycle exit codes. A shared skill and reference define the semantics; every task-creating/advancing command declares and enforces its phase behavior. Human expectations remain a compatibility view, never closure authority for armed lanes.

**Tech Stack:** Python 3 standard library, Bash, Bats, Markdown command contracts, JSON/JSONL, Git object/ancestry checks, `ssh-keygen -Y` signatures, and the GitHub repository-rules API for the first `git-protected-ref-v1` profile.

---

## Architecture Impact

This adds one shared validation seam rather than replacing PRD, expectations, spec graph, QA, or compliance. Armed tasks gain a private source provider, a public event ledger, signed evidence receipts, and a protected-ref head anchor. Existing tasks remain historical until an exact `canon_epoch`; armed adoption is monotonic. Commands stay Markdown contracts, while the Python core is the sole parser/deriver and the shell wrapper is the stable invocation boundary.

## Detailed Design

Tasks 2-5 implement ledger/durability, provider trust, evidence, migration, and derived state. Tasks 6-8 wire every task-advancing command and close quick/content/replay bypasses. Task 9 publishes the reference, runs all gates, and establishes the protected-ref release epoch. The PRD is normative for event fields, authority semantics, state transitions, and the one-time genesis exception.

## Security Summary

- Private verbatim bytes never enter the public ledger by default; reports use salted digests and opaque locators.
- Adapters and the evidence runner are argv-only, no-shell, root-confined, time/output/env bounded, and authenticated against pinned trust roots.
- Strict state requires a remote ref verified to reject deletion/non-fast-forward/update; local chain validity is insufficient.
- External text is data and never executed. Secrets remain in credential helpers/signer stores, never argv, logs, fixtures, or committed config.
- S1/S2/S3/S5/S9/S10 apply, and S11 requires a distinct adversarial review because external provider bytes cross into agent-readable evidence.

## Security Design and Threat Model

The defended failures are omitted/private-source mutation, forged evidence or customer acceptance, adapter command injection, credential leakage, ledger rollback/truncation/divergence, unauthorized supersession, symlink/path escape, concurrent writers, crash/disk-full loss, and post-hoc attribution. The trust roots are the consumer registry's allowed signers and a host-protected Git ref. A project whose rules/signature/provider probe fails cannot arm strict mode. The framework cannot prevent deliberate unrecorded work, but it makes that work ineligible for canonical evidence and independently reviewable.

## Immutable pre-work contract

Before Task 2 changes implementation source, freeze the following for TUNE-0585 in `datarim/delivery/TUNE-0585.jsonl` `[to-be-created]` and commit it separately:

- role: `developer` plus subordinate `peer-reviewer` for specification and quality gates;
- skills: `testing`, `ai-quality`, `security-baseline`, `subagent-driven-development`, `verification-before-completion`, `requesting-code-review`;
- blueprint: `PRD-TUNE-0585` at commit `931df32` or its reviewed superseding commit;
- constraints: English-only shipped surface, stdlib-only parser, no shell adapter execution, root-confined paths, no fabricated legacy evidence, protected-branch PR flow;
- policies: `CLAUDE.md`, security baseline, workspace discipline, and operator amendment; the not-yet-created customer-delivery skill is a deliverable, never a bootstrap pin;
- success criteria: V-AC-1 through V-AC-10 in the PRD;
- enabling parent: `TALO-0001`, without claiming that framework artifacts satisfy its visitor-visible requirements.

Genesis uses two commits because the framework cannot self-attest before its runner exists. First commit a bootstrap freeze record after spec approval; then commit a distinct authorization marker over the clean implementation base. Implementation begins only in a descendant of the authorization commit. Raw TDD proves development sequencing but is not canonical evidence. After the runner exists, a present-day mutation/restoration supplies signed canonical RED/GREEN, and the merge to the selected protected ref becomes the monotonic `canon_epoch`.

## Task 1: Close specification and bootstrap dogfood provenance

**Files:**

- Modify: `datarim/prd/PRD-TUNE-0585.md`
- Modify: `datarim/tasks/TUNE-0585-task-description.md`
- Modify: `datarim/tasks/TUNE-0585-expectations.md`
- Create: `datarim/delivery/TUNE-0585.bootstrap.json` `[to-be-created]`
- Create: `datarim/evidence/TUNE-0585/spec-review.json` `[to-be-created]`

**Steps:**

1. Obtain a subordinate exact-blob review of the amended spec and retain its findings/verdict.
2. If the verdict is NO, revise the spec, commit it, and repeat exact-blob review. Do not edit implementation source before YES.
3. Feasibility-probe the concrete genesis profiles: `ssh-keygen -Y` sign/verify with a synthetic key, GitHub rules API showing protected release/default refs, credential-safe authenticated read, and the exact protected-ref resolve protocol. Record stdout/stderr/exit without secrets. A failed trust probe blocks source work. The 2026-08-22 probe confirmed SSH signing/verification and remote read; release-tag ruleset `16418778` is active for `refs/tags/v*` with deletion/non-fast-forward/update blocked and no bypass. Default-branch ruleset `15879567` blocks deletion only, so it is explicitly ineligible for ongoing append anchoring until a dedicated non-fast-forward-protected ledger branch exists.
4. Create the bootstrap freeze record with private operator-amendment source provenance, atomic framework requirements/review, `enabling-v1` pre-registration parent intent `TALO-0001`, evolution disposition, all existing six capability classes, selected `git-immutable-tag-v1` genesis and `git-ssh-v1` signer profiles, and the reviewed spec commit. Commit freeze alone. Do not falsely select the current default branch as a monotonic append authority.
5. Retain the review receipt with reviewer identity, exact commit, findings, and disposition. In a second commit, write the authorization marker over the clean Datarim base. Do not claim a ledger anchor or canonical RED yet.
6. Verify spec → freeze → authorization are three ordered commits descending from exact base `d27b15f`; branch is clean before Task 2.

**Validation:** provider feasibility report exits 0; `git merge-base --is-ancestor d27b15f HEAD`; exact commit ordering is proven; init-task and expectations gates exit 0; subordinate report ends `SPEC READY: YES`.

**Verifies:** V-AC-9.

## Task 2: Drive the core ledger contract RED

**Files:**

- Create: `tests/customer-delivery-gate.bats` `[to-be-created]`
- Create: `tests/fixtures/customer-delivery/` `[to-be-created]`

**Steps:**

1. Add fixtures for valid `none`, enabling, and bilingual-web ledgers plus provider-backed source and child manifests.
2. Add independent mutants for broken event/predecessor hashes, anchored-head rollback/truncation/divergence, source omission/pagination/private-byte mutation, aggregate catch-all requirements, absent/forged atomicity review, missing/dangling mappings, child omission/cycle/cross-project identity, and strict-mode reversion.
3. Add pre-work mutants for every capability class, `Unbound`, em dash, mutable refs, absent freeze blob, missing/wrong authorization marker, dirty/wrong base, and non-descendant implementation.
4. Add evidence/disposition mutants for fabricated/manual/hash-only receipts, forged customer identity, vacuous RED, assertion mismatch, generic/404 live response, matrix-cell alias, missing each matrix cell, wrong deployed SHA, and accepted/returned/rejected/deferred/withdrawn semantics.
5. Add durability mutants for concurrent/divergent writers, duplicate retry, stale lock, short write/disk full, process death around rename, fsync failure, anchor timeout, unanchored recovery, and unauthorized supersession.
6. Run the focused suite before creating the implementation and retain the expected missing-core assertion as raw development RED in `datarim/evidence/TUNE-0585/red/` `[to-be-created]`. It must fail at the intended assertion, not setup, but it is explicitly not a canonical runner attestation.

**Validation:** `bats tests/customer-delivery-gate.bats` exits non-zero at the intended missing-core assertion, not setup; evidence metadata says `development_only: true`.

**Verifies:** V-AC-1, V-AC-2, V-AC-4, V-AC-5, V-AC-7, V-AC-8, V-AC-10.

## Task 3: Implement the append-only ledger, safe adapters, and derived state

**Files:**

- Create: `scripts/customer-delivery-ledger.py` `[to-be-created]`
- Create: `dev-tools/check-customer-delivery.sh` `[to-be-created]`
- Create: `templates/customer-delivery-ledger.jsonl` `[to-be-created]`
- Create: `templates/customer-delivery-project.json` `[to-be-created]`
- Modify: `tests/customer-delivery-gate.bats`

**Steps:**

1. Implement strict JSONL parsing, canonical event hashing, predecessor validation, unique IDs, authority-constrained supersession rules, owner-aware locking, durable fsync/atomic replacement, idempotent retry, recoverable unanchored state, and unknown-schema/event fail-closed behavior.
2. Implement lane classification and immutable project-registry `canon_epoch`; strict adoption is monotonic.
3. Resolve private authoritative source/child manifests and public monotonic head anchors through pinned provider registrations. Invoke adapters with argv and `shell=False`, a fixed cwd, allowlisted environment, executable digest, timeout, output cap, authentication metadata, and strict result schema.
4. Validate source exhaustion without printing verbatim bytes, exact salted digest capture, authenticated atomicity review, typed atomic ACs, parent identity, acyclic children, capability pins, freeze blob, authorization marker, anchored event count/head, and Git ancestry.
5. Derive `not_started`, `in_progress`, `customer_review`, `rework_required`, `blocked`, or `complete`; only accepted requirements pass and authenticated withdrawal removes a denominator item.
6. Expose `init`, `append`, `validate --stage`, `derive`, and `migrate` subcommands. The shell wrapper maps contract findings to 1, usage/integrity to 2, and required-provider failure to 3.
7. Make every focused mutant RED and valid control GREEN.

**Validation:** `bats tests/customer-delivery-gate.bats`; `python3 -m py_compile scripts/customer-delivery-ledger.py`; `dev-tools/check-customer-delivery.sh --task TUNE-0585 --stage plan --root . --format json`.

**Verifies:** V-AC-1, V-AC-2, V-AC-5, V-AC-7, V-AC-8, V-AC-10.

## Task 4: Implement runner-produced RED/GREEN and live evidence

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

## Task 5: Implement deterministic migration and compatibility

**Files:**

- Create: `tests/customer-delivery-migration.bats` `[to-be-created]`
- Modify: `scripts/customer-delivery-ledger.py`
- Modify: `templates/customer-delivery-project.json`

**Steps:**

1. RED-test exact genuine init-task/append-log import, provider pagination, retroactive Overview recovery, legacy evidence text, monotonic adoption, and dual-read sunset.
2. Import genuine bytes/digests as source events; mark agent-authored retroactive seeds `legacy_unverified_source` and implementation/test/deploy prose `legacy_claim`.
3. Ensure neither legacy class satisfies source, pre-work, RED/GREEN, live, visual, or customer-disposition coverage.
4. Require an exact release/version/commit `canon_epoch`, name one compatibility release, and fail after its removal version.
5. Re-run focused migration and core suites GREEN.

**Validation:** `bats tests/customer-delivery-migration.bats tests/customer-delivery-gate.bats`.

**Verifies:** V-AC-7.

## Task 6: Wire pre-work capture and review-to-evolution

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

1. Add command-contract RED tests for L1, L2, review source-kind, atomization, typed surface blueprints, bounded pre-work evolution mutation, freeze, and authorization.
2. Classify every task at init. Armed lanes capture provider-backed source; `none` records a reason and is rejected for customer/visitor intent.
3. Remove false `verbatim` semantics from skipped-init recovery: agent summaries remain unverified legacy source.
4. Require PRD atomization and typed production predicates for armed work regardless of nominal complexity; route L1/L2 through the minimal required pre-work substage.
5. Freeze role, skill, blueprint, constraint, policy, success criterion, source-derived evolution disposition, and target authorization before `/dr-do`.
6. Make `/dr-plan` invoke the architect/skill-creator pre-work evolution substage for reversible task-scoped created/revised artifacts; preserve the Class B hard gate, blocked state, and deterministic resume to refreeze for operating-model changes.
7. Keep expectations as a generated compatibility view and prohibit em dash/Unbound closure.

**Validation:** `bats tests/customer-delivery-command-contract.bats`; expectations/init-task gates for TUNE-0585.

**Verifies:** V-AC-1, V-AC-2, V-AC-3, V-AC-6.

## Task 7: Wire implementation, QA, live matrix, and closure

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

## Task 8: Close quick, content, replay, and future-command bypasses

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

## Task 9: Publish the framework contract and validate all surfaces

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
4. Run independent subordinate exact-head quality review. Fix every blocking finding and re-run the review on the new exact head.
5. Append the quality-review receipt and final evidence hashes; derive TUNE-0585 as `genesis_unanchored`/enabling-verified without claiming customer acceptance or parent delivery for TALO-0001.
6. Commit, push the feature branch, open a protected PR, and require exact-head CI. Do not self-merge unless normal repository authority explicitly permits it.
7. After the reviewed exact head merges through the protected path, resolve the exact ledger blob from the protected release tag, append the immutable-tag receipt, and record that tag as `canon_epoch`. Only then may the universal canon report canonical completion. Talomnia must first register/probe its own dedicated `git-protected-ref-v1` append branch before strict mode.

**Validation:** `bats tests/*.bats`; `bats dev-tools/tests/*.bats`; `./dev-tools/dr-spec-lint.sh --task TUNE-0585 --root . --stage verify --format text`; `./validate.sh`; exact-head CI for the PR head.

**Verifies:** V-AC-1, V-AC-2, V-AC-3, V-AC-4, V-AC-5, V-AC-6, V-AC-7, V-AC-8, V-AC-9, V-AC-10.

## Rollback and preservation

- Every ledger correction is a superseding event; never rewrite evidence history.
- Framework changes are isolated on `feat/TUNE-0585-customer-delivery-canon`; rollback is a normal revert PR, not history rewriting.
- A failed adapter, live probe, matrix cell, or customer disposition leaves the exact requirement blocked with retained evidence.
- Talomnia adoption begins only after the universal release is exact-head green. It uses separate isolated worktrees and does not mutate `talomnia-knowledge` PR #44.

## Test Plan

- Unit/contract: canonical hashes, schema/events, private-source digest checks, atomicity review, typed ACs, state derivation, disposition semantics.
- Integration: Git repositories for ancestry/protected-ref resolution, synthetic SSH signatures, constrained adapter processes, concurrent/crash writer recovery.
- Mutation: every omission, capability class, RED/GREEN assertion, deployment mismatch, matrix cell, forged trust receipt, rollback/truncation, bypass command, and legacy non-coverage boundary.
- Full regression: all root and `dev-tools/` Bats suites, spec graph, English/history/security gates, shellcheck, Python compile/Bandit when available, and `validate.sh`.
- Exact-head: subordinate spec review before implementation; spec compliance then quality review for each implementation task; final adversarial S11 and exact-head quality review before PR readiness.

## Validation Checklist

| Deliverable | Acceptance proof | V-AC |
|---|---|---|
| Closed-world source and atomic mapping | provider omission/private mutation/aggregate mutants RED; authenticated complete control GREEN | V-AC-1 |
| Pre-work ordering | spec/freeze/auth commits plus capability/base/ancestry mutants | V-AC-2 |
| Review evolution | source-kind and missing/post-hoc artifact mutants; `/dr-plan` resume control | V-AC-3 |
| Live delivery | signed RED/GREEN, deploy, semantic probe, eight non-aliased matrix cells, authenticated disposition | V-AC-4 |
| Derived epic state | omitted/cyclic/cross-project child and narrated-complete mutants | V-AC-5 |
| Universal routing | discovered command capabilities; L1/L2/quick/content/replay/new-command mutants | V-AC-6 |
| Migration | exact epoch, one-release sunset, monotonic strict adoption, legacy non-coverage | V-AC-7 |
| Trust boundary | no-shell/argv/env/path/time/output, signature/customer forgery, independent receipt verification | V-AC-8 |
| Genesis | three pre-code commits, development-only raw RED, present-day signed mutation, protected-ref epoch | V-AC-9 |
| Durability | concurrency/retry/stale-lock/crash/disk/anchor/rollback/supersession mutants | V-AC-10 |

## Next Steps

1. Obtain `SPEC READY: YES` on the exact amended spec/plan commit.
2. Commit genesis freeze and authorization separately after the concrete provider feasibility probe.
3. Execute Tasks 2-9 continuously through subordinate implementer → spec review → quality review cycles.
4. Land through the protected PR path; then register and reconcile Talomnia in separate isolated worktrees.

## Path validation

All existing edit/validation targets above must resolve in the exact-base worktree. Every absent path is explicitly marked `[to-be-created]`; no deprecated target is allowed. Run the plan-path validator again after any path revision and before `/dr-do`.

PATH VALIDATION

- checked: 48 unique edit/validation path references;
- present: 34 exact-base paths;
- expected new: 14 paths, each explicitly marked `[to-be-created]`;
- unexpected missing: 0;
- deprecated edit targets: 0 (the only marker hits describe retired concepts inside live current files, not retired target paths);
- runtime-body probe: clean; the plan does not prescribe task-ID provenance in shipped `commands/`, `skills/`, `templates/`, or `CLAUDE.md` bodies.
