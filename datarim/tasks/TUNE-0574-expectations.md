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
  - #### Текущий статус
    - pending

- **2. Every shipped task-ID occurrence is classified and only illustrative examples survive.**
  - wish_id: classify-and-clean-governed-corpus
  - Что хочу проверить: Real provenance stamps and dead task links are removed without weakening their load-bearing rules, while legitimate rendered examples remain inside narrow valid hatches.
  - Как проверить (success criterion): A raw inventory over the ten governed targets is fully classified, both default exemptions are excluded explicitly, and the clean gate loop exits 0 for every target.
  - Связанный AC из PRD: V-AC-2, V-AC-4
  - evidence_type: static
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief and approved design
  - #### Текущий статус
    - pending

- **3. RED evidence proves the tests detect the original defect.**
  - wish_id: preserve-prefixed-red-proof
  - Что хочу проверить: The new tests fail against the pre-fix implementation without stashing, resetting, or altering dirty foreign workspaces, then pass against the fix.
  - Как проверить (success criterion): Evidence records exit 1 and named failing cases against an isolated `origin/main` gate fixture, followed by exit 0 for the same fixed suite.
  - Связанный AC из PRD: V-AC-7
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief and TDD mandate
  - #### Текущий статус
    - pending

- **4. The public site enforces the generic no-hatch rule and is deployed through CI.**
  - wish_id: site-generic-gate-and-deploy
  - Что хочу проверить: A novel prefix fails, adjacent non-ID text passes, the clean site contract is green, the protected site PR merges, and the resulting-main deployment workflow succeeds.
  - Как проверить (success criterion): Site control output, exact-head CI, resulting-main merge SHA, and terminal-success deployment run are all recorded.
  - Связанный AC из PRD: V-AC-8
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief site parity requirement
  - #### Текущий статус
    - pending

- **5. Framework delivery and release are proven at exact immutable revisions.**
  - wish_id: framework-release-provenance
  - Что хочу проверить: The rebased PR head is green, the resulting main tree contains the owned blobs, version 2.65.0 is tagged from that tree, and the GitHub Release and required release attestations are present.
  - Как проверить (success criterion): Evidence includes PR head SHA, required check conclusions, merge/resulting-main SHA, tag target, release URL, and release workflow outcome.
  - Связанный AC из PRD: V-AC-9
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief release requirement
  - #### Текущий статус
    - pending

- **6. The semantic hook probe and released runtime are verified on all three machines.**
  - wish_id: fleet-three-machine-readback
  - Что хочу проверить: arcana-devs, dev-ai, and aether carry the released framework and per-user runtime, pass drift/readback checks, and return the semantic marker from the installed hook; the gated Aether fork remains untouched.
  - Как проверить (success criterion): Exact commands, exit codes, version/ref hashes, drift output, and `grep -F 'missing read targets fail closed' ~/.local/bin/coworker-hook-guard` output are recorded separately for all three machines.
  - Связанный AC из PRD: V-AC-5
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief fleet Definition of Done
  - #### Текущий статус
    - pending

- **7. Full verification, independent compliance, and lifecycle closure are complete.**
  - wish_id: complete-quality-and-archive
  - Что хочу проверить: Full Bats and named gates pass with positive controls, an independent clean-context review finds no unresolved high or medium issue, and archive/state ledgers close only after site, release, and fleet proof.
  - Как проверить (success criterion): QA, compliance, reflection, archive, test logs, and reconciled task indexes all exist and agree on a completed outcome with no unproven acceptance criterion.
  - Связанный AC из PRD: V-AC-1, V-AC-2, V-AC-6, V-AC-8, V-AC-9
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-09T13:52:54Z / 13:52 UTC · /dr-prd · pending → pending · reason: captured from the operator brief Definition of Done
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty on first write)_
