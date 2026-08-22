---
task_id: TUNE-0585
artifact: expectations
schema_version: 2
captured_at: 2026-08-22
captured_by: /dr-prd
status: canonical
agent: architect
parent_init_task: datarim/tasks/TUNE-0585-init-task.md
parent_prd: datarim/prd/PRD-TUNE-0585.md
---

# TUNE-0585 — Operator Expectations

## Ожидания

- **1. Customer remarks become atomic, traceable delivery requirements.**
  - wish_id: atomic-customer-requirement-chain
  - Что хочу проверить: Every authoritative source-manifest item is preserved privately, externally anchored, and maps to one or more stable atomic requirement IDs with typed customer-visible acceptance criteria or an explicit enabling-parent relationship.
  - Как проверить (success criterion): Focused fixtures cover provider pagination/omission, private-source mutation, one-to-one, one-to-many, duplicate, unmapped, aggregate, missing atomicity review, and enabling-parent cases; the validator rejects every broken mapping.
  - Связанный AC из PRD: V-AC-1
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **2. Capability attribution is pinned before implementation.**
  - wish_id: prework-pinned-capability-chain
  - Что хочу проверить: Role, skill, blueprint, constraint, policy, and success-criterion references are immutable before implementation authorization; `Unbound`, mutable refs, missing classes, wrong bases, and post-hoc attribution fail closed.
  - Как проверить (success criterion): Focused mutation cases remove, mutate, reorder, or falsify each binding class, freeze record, authorization marker, and target base; the pre-work gate returns non-zero before implementation is allowed.
  - Связанный AC из PRD: V-AC-2
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **3. Customer reviews force evolution before remediation.**
  - wish_id: review-to-evolution-prework-gate
  - Что хочу проверить: Every source-provider-classified customer-review requirement records a pre-work evolution disposition and immutable artifact references, or a justified reuse disposition, before implementation authorization.
  - Как проверить (success criterion): The review-to-evolution mutation substage and gate reject relabeling, absent dispositions, and created/revised references with no prior artifact mutation; a fully pinned fixture goes GREEN.
  - Связанный AC из PRD: V-AC-3
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **4. User-facing delivery cannot be self-certified by implementation artifacts.**
  - wish_id: live-customer-delivery-proof
  - Что хочу проверить: Tools, docs, tests, and green CI remain supporting evidence only; visitor-visible web work needs runner-produced RED/GREEN proof, exact deployed SHA, semantic live probe, complete non-aliased RU/EN by viewport by theme screenshots, and customer-authenticated acceptance or withdrawal.
  - Как проверить (success criterion): Close-gate fixtures independently omit or forge each evidence class, serve generic/404 pages, alias matrix cells, or use returned/rejected/deferred dispositions and remain blocked; only the complete accepted fixture passes.
  - Связанный AC из PRD: V-AC-4
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **5. Epic state is derived from complete requirement coverage.**
  - wish_id: derived-epic-coverage
  - Что хочу проверить: An epic cannot claim completion while any authoritative source remark or child is omitted, any atomic requirement is uncovered, or any customer-facing requirement lacks live evidence and accepted/withdrawn disposition.
  - Как проверить (success criterion): Coverage fixtures demonstrate that narrated or stored completion cannot override an omitted, cyclic, cross-project, or uncovered child; the derived report names exact missing IDs and exits non-zero.
  - Связанный AC из PRD: V-AC-5
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **6. The canon is universal, documented, reviewed, and safe to adopt.**
  - wish_id: universal-pipeline-adoption
  - Что хочу проверить: Every task-creating or task-advancing Datarim entry point names the correct capture, pre-work, evidence, or closure gate; templates, monotonic migration, constrained adapters, runner provenance, full validation, spec review, and quality review all agree.
  - Как проверить (success criterion): V-AC-6 through V-AC-10 and the full framework suite pass on the exact PR head, and independent Codex reviews report no unresolved blocking finding.
  - Связанный AC из PRD: V-AC-6, V-AC-7, V-AC-8, V-AC-9, V-AC-10
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty on first write)_
