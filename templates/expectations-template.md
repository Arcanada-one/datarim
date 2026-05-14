---
task_id: {TASK-ID}
artifact: expectations
schema_version: 1
captured_at: {YYYY-MM-DD}
captured_by: {/dr-prd | /dr-plan}
status: canonical
agent: {architect | planner}
parent_init_task: {TASK-ID}-init-task.md
parent_prd: ../prd/PRD-{TASK-ID}.md
---

# {TASK-ID} — Ожидания оператора

> **Plain-language operator wishlist.** Каждый пункт — одно проверяемое
> ожидание, сформулированное обычным русским языком. На стадиях `/dr-qa`,
> `/dr-compliance`, `/dr-archive` каждому пункту присваивается статус;
> `partial` или `missed` без `override:` (≥10 символов) блокирует pipeline
> и возвращает работу в `/dr-do` с указанием конкретных `wish_id`.
>
> Контракт схемы: `skills/expectations-checklist.md`.
> Валидатор: `dev-tools/check-expectations-checklist.sh --task {TASK-ID}`.

## Ожидания

- **1. {Заголовок первого ожидания обычными словами, заканчивается точкой.}**
  - wish_id: {kebab-slug; допустима кириллица}
  - Что хочу проверить: {одно-два предложения}
  - Как проверить (success criterion): {конкретный сигнал — путь к файлу,
    вывод команды, видимое поведение}
  - Связанный AC из PRD: {V-AC-N или «—»}
  - #### История статусов
    - {ISO 8601} / {local-time} · {/dr-prd | /dr-plan} · pending → pending · reason: пункт создан при формировании контракта ожиданий
  - #### Текущий статус
    - pending

- **2. {Заголовок второго ожидания.}**
  - wish_id: {kebab-slug}
  - Что хочу проверить: {…}
  - Как проверить (success criterion): {…}
  - Связанный AC из PRD: {V-AC-N или «—»}
  - #### История статусов
    - {ISO 8601} / {local-time} · {/dr-prd | /dr-plan} · pending → pending · reason: пункт создан при формировании контракта ожиданий
  - #### Текущий статус
    - pending

<!-- Добавлять новые ожидания снизу. Сохранять формат полностью —
     валидатор проверяет наличие wish_id, формат строки История статусов и
     значение Текущий статус. -->

## Append-log (operator amendments)

> Дополнения добавляются хронологически. Каждое — отдельная подпись
> (`### <ISO 8601 timestamp> — amendment by <author>`), без таблиц.

_(пусто на момент создания)_
