---
task_id: TUNE-0517
artifact: expectations
schema_version: 2
captured_at: 2026-07-26
captured_by: /dr-init
agent: planner
status: canonical
parent_init_task: TUNE-0517-init-task.md
---

# TUNE-0517 - Ожидания оператора

## Ожидания

- **1. Vendor-default model and effort policy is canonical and cross-linked.**
  - wish_id: vendor-default-policy
  - Что хочу проверить: The framework follows current vendor-default model and effort semantics and distinguishes CLI runtime policy from project dependencies.
  - Как проверить (success criterion): Canonical policy and cross-links exist in the named shipped files and presence tests pass.
  - Связанный AC из PRD: —
  - evidence_type: static
  - #### История статусов
    - 2026-07-26T09:30:00Z / 09:30 UTC · /dr-init · pending → pending · reason: item created during task initialization
    - 2026-07-26T12:00:00Z / 12:00 UTC · /dr-qa · pending → met · reason: canonical policy and cross-link tests passed
    - 2026-07-26T12:20:00Z / 12:20 UTC · /dr-compliance · met → met · reason: compliance replay confirmed canonical policy and cross-links
  - #### Текущий статус
    - met

- **2. Latest CLI guidance is permission-aware and non-blocking.**
  - wish_id: latest-cli-advisory
  - Что хочу проверить: Newest stable CLI agents are preferred, upgrades happen only where permitted, and restricted environments receive an advisory recommendation.
  - Как проверить (success criterion): Shipped policy explicitly preserves permissions, routing, and exit codes.
  - Связанный AC из PRD: —
  - evidence_type: static
  - #### История статусов
    - 2026-07-26T09:30:00Z / 09:30 UTC · /dr-init · pending → pending · reason: item created during task initialization
    - 2026-07-26T12:00:00Z / 12:00 UTC · /dr-qa · pending → met · reason: permission-aware advisory policy is explicit and covered by tests
    - 2026-07-26T12:20:00Z / 12:20 UTC · /dr-compliance · met → met · reason: compliance replay preserved advisory-only routing and exit semantics
  - #### Текущий статус
    - met

- **3. Fleet version awareness is fail-open and autonomous model choice is pre-resolved.**
  - wish_id: fail-open-version-awareness
  - Что хочу проверить: Optional version hints never block backend selection, and autonomous mode uses vendor defaults without asking.
  - Как проверить (success criterion): Shell behavior and policy presence tests pass without changing backend order or failure behavior.
  - Связанный AC из PRD: —
  - evidence_type: empirical
  - #### История статусов
    - 2026-07-26T09:30:00Z / 09:30 UTC · /dr-init · pending → pending · reason: item created during task initialization
    - 2026-07-26T12:00:00Z / 12:00 UTC · /dr-qa · pending → met · reason: runtime tests prove timeout-bounded fail-open behavior and autonomous pre-resolution
    - 2026-07-26T12:20:00Z / 12:20 UTC · /dr-compliance · met → met · reason: runtime replay confirmed timeout-bounded fail-open version hints
  - #### Текущий статус
    - met

- **4. Configuration is de-pinned safely and all hygiene gates pass.**
  - wish_id: depin-and-hygiene
  - Что хочу проверить: Stale model IDs are replaced by vendor-default semantics, the dangling reference is fixed, and validation, ASCII, forbidden-literal, signing, push, and archive gates pass.
  - Как проверить (success criterion): Config assertions, full lint, bats, shellcheck, grep checks, signed commit objects, remote branch state, and archive presence all pass.
  - Связанный AC из PRD: —
  - evidence_type: empirical
  - #### История статусов
    - 2026-07-26T09:30:00Z / 09:30 UTC · /dr-init · pending → pending · reason: item created during task initialization
    - 2026-07-26T12:00:00Z / 12:00 UTC · /dr-qa · pending → met · reason: configuration, validation, hygiene, signing, and remote-state checks passed
    - 2026-07-26T12:20:00Z / 12:20 UTC · /dr-compliance · met → met · reason: compliance replay confirmed configuration, hygiene, signing, and remote state
  - #### Текущий статус
    - met

## Append-log (operator amendments)

_(empty at creation)_
