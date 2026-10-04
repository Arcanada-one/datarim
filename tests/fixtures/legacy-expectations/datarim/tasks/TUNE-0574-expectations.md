---
task_id: TUNE-0574
artifact: expectations
schema_version: 2
captured_at: 2026-08-09
captured_by: /dr-prd
status: canonical
agent: architect
parent_init_task: datarim/tasks/TUNE-0574-init-task.md
parent_prd: datarim/prd/PRD-TUNE-0574.md
---

# TUNE-0574 — Ожидания оператора

## Ожидания

- **1. The gate closes every documented mechanism gap.**
  - wish_id: close-all-gate-gaps
  - Что хочу проверить: The one-target gate scans every governed root and listed text extension, treats malformed hatches as findings, rejects provenance labels inside valid hatches, and uses exact exemptions.
  - Как проверить (success criterion): `bats tests/task-id-gate.bats` exits 0 and its named cases cover extensions, callers, malformed markers, label forms, boundaries, exact whitelist matching, and diff failures.
  - Связанный AC из PRD: V-AC-1, V-AC-3, V-AC-4, V-AC-7
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief and approved design
    - 2026-08-09T15:22:14Z / 15:22 UTC · /dr-qa · pending → met · reason: 53 focused cases cover every required parser, traversal, boundary, whitelist, and diff failure mode and all pass
  - #### Текущий статус
    - met

- **2. Every shipped task-ID occurrence is classified and only illustrative examples survive.**
  - wish_id: classify-and-clean-governed-corpus
  - Что хочу проверить: Real provenance stamps and dead task links are removed without weakening their load-bearing rules, while legitimate rendered examples remain inside narrow valid hatches.
  - Как проверить (success criterion): A raw inventory over the ten governed targets is fully classified, both default exemptions are excluded explicitly, and the clean gate loop exits 0 for every target.
  - Связанный AC из PRD: V-AC-2, V-AC-4
  - evidence_type: static
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief and approved design
    - 2026-08-09T15:22:14Z / 15:22 UTC · /dr-qa · pending → met · reason: the raw inventory is classified, exact history surfaces are exempt, and every governed target passes the clean gate
  - #### Текущий статус
    - met

- **3. RED evidence proves the tests detect the original defect.**
  - wish_id: preserve-prefixed-red-proof
  - Что хочу проверить: The new tests fail against the pre-fix implementation without stashing, resetting, or altering dirty foreign workspaces, then pass against the fix.
  - Как проверить (success criterion): Evidence records exit 1 and named failing cases against an isolated `origin/main` gate fixture, followed by exit 0 for the same fixed suite.
  - Связанный AC из PRD: V-AC-7
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief and TDD mandate
    - 2026-08-09T15:22:14Z / 15:22 UTC · /dr-qa · pending → met · reason: the isolated pre-fix gate returned exit 1 with 24 of 50 cases failing and the fixed gate returns exit 0 with 53 of 53 passing
  - #### Текущий статус
    - met

- **4. The public site enforces the generic no-hatch rule and is deployed through CI.**
  - wish_id: site-generic-gate-and-deploy
  - Что хочу проверить: A novel prefix fails, adjacent non-ID text passes, the clean site contract is green, the protected site PR merges, and the resulting-main deployment workflow succeeds.
  - Как проверить (success criterion): Site control output, exact-head CI, resulting-main merge SHA, and terminal-success deployment run are all recorded.
  - Связанный AC из PRD: V-AC-8
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief site parity requirement
    - 2026-08-09T15:22:14Z / 15:22 UTC · /dr-qa · pending → met · reason: the novel-prefix control fails as intended, the clean 448-route contract passes, both protected changes landed, and resulting-main deployment succeeded
  - #### Текущий статус
    - met

- **5. Framework delivery and release are proven at exact immutable revisions.**
  - wish_id: framework-release-provenance
  - Что хочу проверить: The rebased PR head is green, the resulting main tree contains the owned blobs, version 2.65.0 is tagged from that tree, and the GitHub Release and required release attestations are present.
  - Как проверить (success criterion): Evidence includes PR head SHA, required check conclusions, merge/resulting-main SHA, tag target, release URL, and release workflow outcome.
  - Связанный AC из PRD: V-AC-9
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief release requirement
    - 2026-08-09T15:22:14Z / 15:22 UTC · /dr-qa · pending → pending · reason: implementation is merge-ready; protected framework merge and release are downstream gates not yet reached
    - 2026-08-09T16:48:00Z / 16:48 UTC · /dr-qa · pending → met · reason: protected PR 352 merged to c0e283eb22b9b052197f93f96ab165e833b9e17f, tag v2.65.0 targets that commit, release run 31322665918 attempt 2 succeeded, and all five release artifacts passed checksum, signature, attestation, SBOM, and version verification
  - #### Текущий статус
    - met

- **6. The semantic hook probe and released runtime are verified on all three machines.**
  - wish_id: fleet-three-machine-readback
  - Что хочу проверить: The primary canonical runtime, secondary canonical runtime, and secondary per-user runtime carry the release, pass drift/readback checks, and return the semantic marker from the installed hook; the separately gated project checkout remains untouched.
  - Как проверить (success criterion): Exact commands, exit codes, version/ref hashes, drift output, and `grep -F 'missing read targets fail closed' ~/.local/bin/coworker-hook-guard` output are recorded separately for all three machines.
  - Связанный AC из PRD: V-AC-5
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief fleet Definition of Done
    - 2026-08-09T15:22:14Z / 15:22 UTC · /dr-qa · pending → pending · reason: the semantic probe is implemented and locally verified; three-machine release sync is a downstream gate not yet reached
    - 2026-08-09T16:48:00Z / 16:48 UTC · /dr-qa · pending → met · reason: the three current named runtime surfaces resolve to the primary canonical checkout, the secondary canonical checkout, and its per-user runtime; all carry c0e283eb22b9b052197f93f96ab165e833b9e17f and version 2.65.0, pass all ten scanner calls, and return the semantic hook marker while the separately gated project checkout retained its original commit
  - #### Текущий статус
    - met

- **7. Full verification, independent compliance, and lifecycle closure are complete.**
  - wish_id: complete-quality-and-archive
  - Что хочу проверить: Full Bats and named gates pass with positive controls, an independent clean-context review finds no unresolved high or medium issue, and archive/state ledgers close only after site, release, and fleet proof.
  - Как проверить (success criterion): QA, compliance, reflection, archive, test logs, and reconciled task indexes all exist and agree on a completed outcome with no unproven acceptance criterion.
  - Связанный AC из PRD: V-AC-1, V-AC-2, V-AC-6, V-AC-8, V-AC-9
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief Definition of Done
    - 2026-08-09T15:22:14Z / 15:22 UTC · /dr-qa · pending → pending · reason: local QA and independent review pass; framework delivery, release, fleet readback, and archive remain downstream gates
    - 2026-08-09T16:48:00Z / 16:48 UTC · /dr-qa · pending → met · reason: 3257 full tests, focused controls, independent reviews, protected framework and site delivery, verified release, fleet readback, final QA and compliance replay, reflection, archive document, and reconciled task indexes agree on closure
  - #### Текущий статус
    - met

## Append-log (operator amendments)

_(empty on first write)_

### 2026-08-09T16:48:00Z — autonomous closure decisions

- The publisher received no runner for 45 minutes. After proving there were no
  steps, deployment statuses, or release object, one bounded cancel-and-rerun
  was performed for the same immutable tag; attempt 2 completed successfully.
- Current inventory resolves the third requested fleet label to the per-user
  runtime on the secondary host rather than a separate live node. Both canonical
  checkouts and the user runtime were synchronized. The separately gated project
  checkout was read back only and retained its original commit.
