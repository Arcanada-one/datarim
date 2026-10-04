---
id: TUNE-0530
title: "Rework stack selection: from prescribed stacks to justified proposals"
status: completed
completed_date: 2026-07-29
complexity: L3
type: framework
project: Datarim
related:
  - PR #264 (implementation)
  - PR #265 (compliance artifacts)
archive_doc: documentation/archive/framework/archive-TUNE-0530.md
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 0
  false_positive: 0
  n_a: true
  dogfood_window: tune-0530
---

# TUNE-0530 — Archive

## Начальная задача

Пересмотреть зашитые в Датарим правила выбора стеков — от жёстких предписаний к обоснованным предложениям с альтернативами и trade-offs, которые оператор видит и выбирает на этапе PRD/plan.

## Как решили

- **Заменить prescriptive таблицу «Project Type → Required Stack» на guidance catalog** — выполнено. `skills/tech-stack/SKILL.md` полностью переписан: одноимённая секция заменена на «Starting Points & Alternatives» с тремя колонками (Default Recommendation | Viable Alternatives | When to Reconsider). Каждая строка показывает альтернативы и verifiable условия когда стоит пересмотреть выбор.
- **Добавить механизм Stack Proposal с 2-3 кандидатами и trade-offs** — выполнено. Добавлен Trigger Classifier (6 сигналов + default catch-all), 10-факторный proposal template (включая Security posture и Escape velocity), Decision-Making Method, Immutability and Binding с Return-to-Source escape sequence и Security-Emergency Fast-Track.
- **Добавить пропущенные домены** — выполнено. Пять новых доменов: Cross-Platform CLI, Desktop Application, Systems Daemon/Service, Data/ML Pipeline, WASM Module. Rust (8 rows) и Go (12 rows) как first-class options.
- **Разрешить противоречие со stack-agnostic-gate** — выполнено. Whitelist rationale обновлён: «designated technology guidance file».
- **Врезать proposal-шаг в /dr-prd и /dr-plan** — выполнено. `dr-prd.md` Step 2.5, `dr-plan.md` Step 6, `dr-init.md` line 173. Агенты обновлены.
- **bats тесты на проводку** — выполнено. 10 тестов (T1-T10), все проходят.
- **Валидационный dry-run на кейсе Control Arcana** — выполнено. 3 candidate stacks (MUI, Tailwind+TanStack, Mantine) с 10-factor trade-offs.
- **Консилиум на Fable 5** (уточнение брифа) — выполнено. 5/5 panelists conditional support, 15 design decisions, 3 dissents recorded, failure mode table.
- **VERSION bump 2.58.0 → 2.59.0** (уточнение брифа) — выполнено.
- **Аудит prescription surfaces** (уточнение брифа) — выполнено. PRD § Context Analysis: все prescriptive строки с file:line, wiring и последствиями отклонения.
- **Дизайн механизма замены через Fable 5 + consilium** (уточнение брифа) — выполнено. Creative doc с 15 design decisions и failure mode table.
- **bats-тесты на проводку и форму proposal** (уточнение брифа) — выполнено. 10 тестов, проверяющих wiring и mandatory proposal shape, все проходят.
- **Валидационный dry-run Control Arcana** (уточнение брифа) — выполнено. Dry-run демонстрирует что новый механизм surface'ит выбор который старый prescriptive подход подавлял.

## Артефакты задачи

### Изменённые файлы (framework runtime, PR #264 + #265)
- `skills/tech-stack/SKILL.md` — полная переработка (355 строк изменено)
- `skills/evolution/stack-agnostic-gate.md` — обновлён whitelist rationale
- `commands/dr-prd.md` — добавлен Step 2.5
- `commands/dr-plan.md` — расширен Step 6
- `commands/dr-init.md` — обновлён line 173
- `agents/architect.md` — обновлён line 30
- `agents/planner.md` — обновлён line 32
- `VERSION` — 2.58.0 → 2.59.0
- `CLAUDE.md` — updated version
- `README.md` — updated version badge
- `tests/test-tech-stack-proposal.bats` — новый файл (10 тестов)

### Артефакты workflow
- `datarim/prd/PRD-TUNE-0530.md` — PRD с аудитом, research sweep, 10 V-AC
- `datarim/plans/TUNE-0530-plan.md` — 7-phase implementation plan
- `datarim/creative/creative-TUNE-0530-architecture-stack-proposal-mechanism.md` — Fable 5 consilium
- `datarim/qa/qa-report-TUNE-0530.md` — 6-layer QA (CONDITIONAL_PASS)
- `datarim/reports/compliance-report-TUNE-0530.md` — 7-step hardening (COMPLIANT)
- `datarim/reflection/reflection-TUNE-0530.md` — 2 Class A + 1 Class B evolution proposals
- `datarim/tasks/TUNE-0530-validation-dry-run.md` — Control Arcana dry-run
- `datarim/tasks/TUNE-0530-expectations.md` — 5/5 wishes met

## Следующие шаги

Всё закрыто.

---

## Дополнительно для аудита

### verification_outcome
- caught_by_verify: 0 (n/a — /dr-verify not invoked for this task)
- missed_by_verify: 0
- false_positive: 0
- n_a: true
- dogfood_window: tune-0530

### Acceptance Criteria

| AC | Status | Evidence |
|----|--------|----------|
| V-AC-1: Audit completeness | Met | PRD § Context Analysis — 15+ rows with file:line + wiring |
| V-AC-2: Mechanism design | Met | Starting Points table, 5 new domains, Rust 8 rows, Go 12 rows, Decision-Making Method |
| V-AC-3: Command wiring | Met | dr-prd.md Step 2.5, dr-plan.md Step 6, dr-init.md line 173 |
| V-AC-4: Agent loading | Met | architect.md:30, planner.md:32 updated |
| V-AC-5: Gate coherence | Met | Whitelist rationale updated |
| V-AC-6: bats — proposal shape | Met | 10/10 bats tests pass (T1, T3, T5, T6, T7, T9) |
| V-AC-7: bats — trigger behaviour | Met | 10/10 bats tests pass (T2) |
| V-AC-8: Validation dry-run | Met | 3 candidates with 10-factor trade-offs |
| V-AC-9: Immutability binding | Met | Escape sequence + Security-Emergency Fast-Track documented |
| V-AC-10: Decision tree | Met | Mermaid diagram contains Trigger Classifier + Proposal nodes |

### Lessons Learned

1. Fable 5 consilium caught design gaps (Security posture, Escape velocity, trigger catch-all) that survived PRD review — L3+ framework changes touching ≥3 agents should run multi-model consilium.
2. The table format change alone (Strategist's MVP) addresses 80% of the defect; the proposal mechanism addresses the remaining 20%.
3. Structural bats tests for shipped markdown skills are fast (<1s), deterministic, and catch real regressions during development.

Full reflection: `datarim/reflection/reflection-TUNE-0530.md`

### Operator Handoff

Всё закрыто. Три remaining risks задокументированы в compliance report: (1) Rust/Go security guidance gap, (2) toolchain reform dissent, (3) spec-graph metadata drift. Follow-up tasks TUNE-0532 и TUNE-0533 созданы в backlog.

### Related
- PR #264: https://github.com/Arcanada-one/datarim/pull/264
- PR #265: https://github.com/Arcanada-one/datarim/pull/265
- PRD: `datarim/prd/PRD-TUNE-0530.md`
- Plan: `datarim/plans/TUNE-0530-plan.md`
- Creative: `datarim/creative/creative-TUNE-0530-architecture-stack-proposal-mechanism.md`
- Reflection: `datarim/reflection/reflection-TUNE-0530.md`
- Follow-ups: TUNE-0532 (domain security guidance), TUNE-0533 (toolchain reform monitor)
