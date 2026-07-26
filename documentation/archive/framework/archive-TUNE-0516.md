---
id: TUNE-0516
title: Codify orchestration hygiene invariants
status: archived
completed_date: 2026-07-26
complexity: L2
type: framework
project: Datarim
related: []
archive_doc: documentation/archive/framework/archive-TUNE-0516.md
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 0
  false_positive: 0
  n_a: true
  dogfood_window: "TUNE-0516-2026-07"
---

# Архив: TUNE-0516 — Гигиена оркестрации

## Начальная задача

Закрепить два недостающих правила оркестрации, проверить их и пройти полный
цикл задачи без изменения маршрутизации.

## Как решили

- **«Каждая задача работает в своей сессии, рабочем дереве и ветке».** выполнено. Каноническое правило добавлено в раздел управления очередью.
- **«Параллельные задачи не нужно искусственно выстраивать последовательно».** выполнено. Вопрос оператору требуется только при общей ветке или общих целевых файлах.
- **«Обе команды должны ссылаться на единое правило».** выполнено. Добавлено по одной ссылке без изменения логики.
- **«Пример должен быть необязательным и использовать заполнители».** выполнено. Пример явно назван ненормативным и не содержит частной инфраструктуры.
- **«Смена статуса в отслеживаемом рабочем файле сразу фиксируется и отправляется».** выполнено. Отдельно сказано, что правило не требует фиксировать незавершённый код.
- **«Добавить проверку присутствия нового правила».** выполнено. Шесть проверок покрывают оба правила, ссылки и исправление маркера.
- **«Исправить устаревший общий маркер автоматического режима».** выполнено. Документация теперь указывает маркер конкретной задачи.
- **«Сохранить английский и нейтральный публичный текст».** выполнено. Добавленные строки прошли проверки символов и запрещённых литералов.
- **«Пройти полный цикл и немедленно отправлять смены статуса».** выполнено. Все контрольные точки подписаны и отправлены; задача снята с активных индексов.
- **«Параллельная оркестрация закреплена как норма (уточнение брифа)».** выполнено. Правило, границы и ссылки подтверждены проверками.
- **«Смена статуса сохраняется сразу (уточнение брифа)».** выполнено. Правило и отличие от незавершённого кода подтверждены.
- **«Маркер автоматического режима исправлен (уточнение брифа)».** выполнено. Старый маркер отсутствует в строке команды.
- **«Публичная поверхность и полный цикл чисты (уточнение брифа)».** выполнено. Полный набор проверок зелёный, постоянный архив создан.

## Артефакты задачи

- `skills/datarim-system/backlog-and-routing.md`
- `skills/datarim-system/command-and-archive-rules.md`
- `commands/dr-auto.md`
- `commands/dr-orchestrate.md`
- `CLAUDE.md`
- `tests/tune-0516-orchestration-hygiene.bats`
- `datarim/qa/qa-report-TUNE-0516.md`
- `datarim/reports/compliance-report-TUNE-0516.md`
- `datarim/reflection/reflection-TUNE-0516.md`

## Следующие шаги

всё закрыто

---

## Дополнительно для аудита

### verification_outcome

- caught_by_verify: 0
- missed_by_verify: 0
- false_positive: 0
- n_a: true
- dogfood_window: TUNE-0516-2026-07

### Acceptance Criteria

<!-- gate:literal -->
| AC | Status | Evidence |
|---|---|---|
| Parallel-default rule and isolation boundary | pass | backlog-and-routing section and focused bats |
| Command cross-links | pass | dr-auto and dr-orchestrate links |
| Immediate status persistence and WIP distinction | pass | command-and-archive rule and focused bats |
| Per-task auto marker | pass | CLAUDE.md row and focused bats |
| Public-surface hygiene | pass | ASCII and forbidden-literal added-line scans |
| Repository gates | pass | validate PASS; bats 2,084/2,084; shellcheck 197 files |
| Signed pushed lifecycle and archive | pass | SSH gpgsig blocks; HEAD/upstream equality; this archive |
<!-- /gate:literal -->

### Lessons Learned

- Scan complete added lines when replacing an existing long public row.
- Unset ambient variables for tests whose case explicitly requires their absence.
- Для длинных наборов проверок следует использовать одну терминальную сессию, чтобы временные данные не мешали друг другу.

### Operator Handoff

всё закрыто

### Related

- Parent PRD: none
- Plan: preserved in version history at revision `00a1767`
- Reflection: `datarim/reflection/reflection-TUNE-0516.md`
- Follow-ups: none
