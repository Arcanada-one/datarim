---
task_id: {TASK-ID}
artifact: expectations
schema_version: 2
captured_at: {YYYY-MM-DD}
captured_by: {/dr-init | /dr-prd | /dr-plan}
status: canonical
agent: {planner | architect}
parent_init_task: {TASK-ID}-init-task.md
parent_prd: ../prd/PRD-{TASK-ID}.md
---

# {TASK-ID} — Ожидания оператора

> **Plain-language operator wishlist.** Каждый пункт — одно проверяемое
> ожидание, сформулированное обычным русским языком. На стадиях `/dr-qa`,
> `/dr-compliance`, `/dr-archive` каждому пункту присваивается статус;
> `partial` или `missed` без `override:` (≥10 символов) блокирует pipeline
> и возвращает работу в `/dr-do` с указанием конкретных `wish_id`.
> Строка `override:` — child wish-bullet с отступом **ровно 2 пробела**
> (`  - override: <текст ≥10 символов>`), на одном уровне с `wish_id`/`evidence_type`,
> НЕ вложена под `#### Текущий статус` (4 пробела) — иначе валидатор её не видит и держит BLOCKED.
>
> Контракт схемы: `skills/expectations-checklist/SKILL.md`.
> Валидатор: `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task {TASK-ID}`.

## Ожидания

- **1. {Заголовок первого ожидания обычными словами, заканчивается точкой.}**
  - wish_id: {kebab-slug; допустима кириллица}
  - Что хочу проверить: {одно-два предложения}
  - Как проверить (success criterion): {конкретный сигнал — путь к файлу,
    вывод команды, видимое поведение}
  - Связанный AC из PRD: {V-AC-N или «—»}
  - evidence_type: {empirical | static | measurement}
  - #### История статусов
    - {ISO 8601} / {local-time} · {/dr-init | /dr-prd | /dr-plan} · pending → pending · reason: пункт создан при формировании контракта ожиданий
  - #### Текущий статус
    - pending

- **2. {Заголовок второго ожидания.}**
  - wish_id: {kebab-slug}
  - Что хочу проверить: {…}
  - Как проверить (success criterion): {…}
  - Связанный AC из PRD: {V-AC-N или «—»}
  - evidence_type: {empirical | static | measurement}
  - #### История статусов
    - {ISO 8601} / {local-time} · {/dr-init | /dr-prd | /dr-plan} · pending → pending · reason: пункт создан при формировании контракта ожиданий
  - #### Текущий статус
    - pending

<!-- Добавлять новые ожидания снизу. Сохранять формат полностью —
     валидатор проверяет наличие wish_id, формат строки История статусов и
     значение Текущий статус. -->

<!-- OPTIONAL: verification_mode axis (schema v3 only).
     Distinguishes a one-off manual check from a reproducible/wired check.
     To opt in: bump schema_version to 3 in frontmatter, then add:

  - verification_mode: reproducible          # one-off | reproducible
  - evidence_artifact: tests/my-suite.bats   # path, test-id, or CI-job-name

     When verification_mode: reproducible, the validator requires
     evidence_artifact and resolves it two ways: (1) test -f, (2) grep -rqF
     across *.bats / *.sh / *.yml / *.yaml under the repo root.
     Missing or unresolvable → error verification-not-wired (advisory at
     /dr-qa Layer 3b, hard at /dr-compliance).
     See skills/expectations-checklist/SKILL.md § verification_mode axis.
-->

## Append-log (operator amendments)

> Дополнения добавляются хронологически. Каждое — отдельная подпись
> (`### <ISO 8601 timestamp> — amendment by <author>`), без таблиц.

_(пусто на момент создания)_
