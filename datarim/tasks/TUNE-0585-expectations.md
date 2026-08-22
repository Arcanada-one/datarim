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
  - Что хочу проверить: Every verbatim customer remark is preserved and maps to one or more stable atomic requirement IDs with visitor-visible acceptance criteria or an explicit enabling-parent relationship.
  - Как проверить (success criterion): Focused fixtures cover one-to-one, one-to-many, duplicate, unmapped, and enabling-parent cases; the validator rejects every broken mapping.
  - Связанный AC из PRD: V-AC-1
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **2. Capability attribution is pinned before implementation.**
  - wish_id: prework-pinned-capability-chain
  - Что хочу проверить: Role, skill, blueprint, constraint, policy, and success-criterion references are immutable before implementation begins; `Unbound`, mutable refs, missing classes, and post-hoc attribution fail closed.
  - Как проверить (success criterion): Focused mutation cases remove, mutate, reorder, or back-date each binding class and the pre-work gate returns non-zero before implementation is allowed.
  - Связанный AC из PRD: V-AC-2
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **3. Customer reviews force evolution before remediation.**
  - wish_id: review-to-evolution-prework-gate
  - Что хочу проверить: Every customer-review requirement records a pre-work evolution disposition and immutable artifact references, or a justified reuse disposition, before implementation starts.
  - Как проверить (success criterion): The review-to-evolution gate is wired into the pre-work lifecycle and a review fixture with no evolution disposition goes RED while a fully pinned fixture goes GREEN.
  - Связанный AC из PRD: V-AC-3
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **4. User-facing delivery cannot be self-certified by implementation artifacts.**
  - wish_id: live-customer-delivery-proof
  - Что хочу проверить: Tools, docs, tests, and green CI remain supporting evidence only; visitor-visible work needs RED/GREEN proof, exact deployed SHA, live probe, complete RU/EN by viewport by theme screenshots, and customer disposition.
  - Как проверить (success criterion): Close-gate fixtures independently omit each evidence class and remain blocked; only the complete user-facing fixture passes.
  - Связанный AC из PRD: V-AC-4
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **5. Epic state is derived from complete requirement coverage.**
  - wish_id: derived-epic-coverage
  - Что хочу проверить: An epic cannot claim completion while any source remark is unmapped, any atomic requirement is uncovered, or any customer-facing requirement lacks live evidence and disposition.
  - Как проверить (success criterion): Coverage fixtures demonstrate that narrated or stored completion cannot override an uncovered child; the derived report names exact missing requirement IDs and exits non-zero.
  - Связанный AC из PRD: V-AC-5
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

- **6. The canon is universal, documented, reviewed, and safe to adopt.**
  - wish_id: universal-pipeline-adoption
  - Что хочу проверить: Every relevant Datarim lifecycle command names the correct capture, pre-work, evidence, or closure gate; templates, migration guidance, security checks, full validation, spec review, and quality review all agree.
  - Как проверить (success criterion): Command-wiring tests and the full framework suite pass on the exact PR head, and two independent Codex reviews report no unresolved high or medium finding.
  - Связанный AC из PRD: V-AC-6
  - evidence_type: empirical
  - #### История статусов
    - 2026-08-22T07:20:00Z / 07:20 UTC · /dr-prd · pending → pending · reason: captured from the approved operator amendment
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty on first write)_
