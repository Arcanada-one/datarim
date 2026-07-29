---
task_id: TUNE-0530
artifact: expectations
schema_version: 2
captured_at: 2026-07-29
captured_by: /dr-init
status: canonical
agent: planner
parent_init_task: TUNE-0530-init-task.md
---

# TUNE-0530 — Ожидания оператора

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
> Валидатор: `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task TUNE-0530`.

## Ожидания

- **1. Аудит всех поверхностей, где Датарим сейчас предписывает конкретные стеки — с file:line, кто загружает, что происходит при отклонении.**
  - wish_id: audit-prescription-surfaces
  - Что хочу проверить: каждая точка в runtime, где сегодня жёстко назван конкретный стек/фреймворк, задокументирована с указанием файла, строки, механизма загрузки и последствий отклонения.
  - Как проверить (success criterion): наличие в плане или PRD полной таблицы аудита с колонками file, line, prescription, loaded-by, deviation-behaviour; каждая строка проверяема через grep.
  - Связанный AC из PRD: V-AC-1
  - evidence_type: static
  - #### История статусов
    - 2026-07-29 / 2026-07-29 · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
    - 2026-07-29 / 2026-07-29 · /dr-qa · pending → met · reason: аудит выполнен в PRD § Context Analysis, все prescriptive поверхности задокументированы с file:line и wiring
  - #### Текущий статус
    - met

- **2. Дизайн (Fable 5 + consilium) механизма замены: 2-3 viable candidate stack-а с явными trade-offs и рекомендацией на этапе PRD/plan.**
  - wish_id: design-candidate-stacks-with-tradeoffs
  - Что хочу проверить: на выходе дизайна оператор получает не один mandated stack, а обоснованный выбор из 2-3 вариантов с trade-offs, с рекомендацией агента и с возможностью оператору выбрать или утвердить.
  - Как проверить (success criterion): design-документ содержит (a) метод выбора candidate stacks, (b) формат proposal-блока с alternatives + rationale + recommendation, (c) триггеры когда вопрос вообще стоит задавать, (d) разрешение противоречия со stack-agnostic-gate.
  - Связанный AC из PRD: V-AC-2, V-AC-5
  - evidence_type: static
  - #### История статусов
    - 2026-07-29 / 2026-07-29 · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
    - 2026-07-29 / 2026-07-29 · /dr-qa · pending → met · reason: Fable 5 consilium panel 5/5 conditional support, 15 design decisions (D-1..D-15), dissent recorded, creative doc complete
  - #### Текущий статус
    - met
  - wish_id: design-candidate-stacks-with-tradeoffs
  - Что хочу проверить: на выходе дизайна оператор получает не один mandated stack, а обоснованный выбор из 2-3 вариантов с trade-offs, с рекомендацией агента и с возможностью оператору выбрать или утвердить.
  - Как проверить (success criterion): design-документ содержит (a) метод выбора candidate stacks, (b) формат proposal-блока с alternatives + rationale + recommendation, (c) триггеры когда вопрос вообще стоит задавать, (d) разрешение противоречия со stack-agnostic-gate.
  - Связанный AC из PRD: V-AC-2, V-AC-5
  - evidence_type: static
  - #### История статусов
    - 2026-07-29 / 2026-07-29 · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
    - 2026-07-29 / 2026-07-29 · /dr-qa · pending → met · reason: аудит выполнен в PRD § Context Analysis, все prescriptive поверхности задокументированы с file:line и wiring
  - #### Текущий статус
    - met

- **3. Имплементация: переработка skills/tech-stack/, врезка proposal-шага в /dr-prd и /dr-plan, добавление пропущенных доменов (cross-platform CLI/desktop, systems services).**
  - wish_id: implement-rewired-tech-stack
  - Что хочу проверить: (a) `skills/tech-stack/SKILL.md` больше не содержит таблицу «Project Type → Required Stack» в прежнем prescriptive виде; (b) `/dr-prd` и `/dr-plan` включают шаг генерации stack proposal с alternatives + trade-offs; (c) Rust и Go — first-class options для релевантных доменов; (d) противоречие со stack-agnostic-gate разрешено когерентно.
  - Как проверить (success criterion): (a) grep по `skills/tech-stack/SKILL.md` не находит prescriptive формулировок типа «MANDATORY» в адрес конкретного стека; (b) `commands/dr-prd.md` и `commands/dr-plan.md` содержат явные ссылки на stack-proposal шаг; (c) `bats` тесты проходят.
  - Связанный AC из PRD: V-AC-3, V-AC-4, V-AC-9, V-AC-10
  - evidence_type: static
  - #### История статусов
    - 2026-07-29 / 2026-07-29 · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
    - 2026-07-29 / 2026-07-29 · /dr-qa · pending → met · reason: skills/tech-stack/SKILL.md полностью переписан — Starting Points & Alternatives таблица, Trigger Classifier, 10-factor proposal template, 5 новых доменов, Rust+Go first-class options, immutability binding с security-emergency fast-track
  - #### Текущий статус
    - met

- **4. bats-тесты на проводку (wiring) и обязательную форму proposal (alternatives + rationale + recommendation).**
  - wish_id: bats-tests-wiring-and-proposal-shape
  - Что хочу проверить: тесты падают если stack proposal не содержит alternatives, rationale или recommendation; тесты проверяют что proposal-шаг действительно вызывается на /dr-prd и /dr-plan для новых проектов/сервисов.
  - Как проверить (success criterion): `bats tests/` показывает ≥2 теста с именами, содержащими stack-proposal или tech-stack; тесты проверяют поведение (wiring), а не presence prose.
  - Связанный AC из PRD: V-AC-6, V-AC-7
  - evidence_type: static
  - #### История статусов
    - 2026-07-29 / 2026-07-29 · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
    - 2026-07-29 / 2026-07-29 · /dr-qa · pending → met · reason: 10 bats тестов (T1-T10) все проходят — проверяют proposal shape, trigger classifier, отсутствие prescriptive языка, Rust+Go first-class, immutability binding, security factor, escape velocity, новые домены, licence/cost split, backend-standards boundary
  - #### Текущий статус
    - met

- **5. Валидационный dry-run: применить новый механизм к кейсу Control Arcana (Tailwind vs MUI) и показать что он бы выдал на этапе PRD/plan.**
  - wish_id: validation-dry-run-control-arcana
  - Что хочу проверить: новый механизм на реальном кейсе Control Arcana surface'ит выбор Tailwind vs MUI с trade-offs, который прежний prescriptive подход не показал.
  - Как проверить (success criterion): в archive или compliance report есть секция с dry-run применением к Control Arcana; результат содержит ≥2 candidate stacks с rationale.
  - Связанный AC из PRD: V-AC-8
  - evidence_type: empirical
  - #### История статусов
    - 2026-07-29 / 2026-07-29 · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
    - 2026-07-29 / 2026-07-29 · /dr-qa · pending → met · reason: dry-run применён к кейсу Control Arcana — 3 candidate stacks (MUI, Tailwind+TanStack, Mantine) с 10-factor trade-offs; демонстрирует что старый prescriptive подход не показал бы выбор MUI vs Tailwind
  - #### Текущий статус
    - met

## Append-log (operator amendments)

> Дополнения добавляются хронологически. Каждое — отдельная подпись
> (`### <ISO 8601 timestamp> — amendment by <author>`), без таблиц.

_(пусто на момент создания)_
