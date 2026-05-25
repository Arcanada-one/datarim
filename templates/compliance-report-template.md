---
task_id: {TASK-ID}
date: {YYYY-MM-DD}
verdict: {COMPLIANT|COMPLIANT_WITH_NOTES|NON-COMPLIANT}
scope: {optional one-line scope description}
---

# Compliance-отчёт: {TASK-ID} — {Title}

## Начальная задача

{Одно предложение обычным языком, что требовалось проверить и закрепить. Источник — `tasks/{TASK-ID}-init-task.md` § Operator brief (verbatim), сжатое до одной фразы.}

## Как решили

{Маркированный список, по одному пункту на каждый bullet операторского брифа из `tasks/{TASK-ID}-init-task.md` в исходном порядке. Если есть `tasks/{TASK-ID}-expectations.md` — каждый пункт § Ожидания добавляется в тот же список с пометкой «(уточнение брифа)». Без таблиц, без вложенных bullet. Банлист `skills/human-summary/banlist.txt` применяется к комментариям.}

- **«{цитата пункта 1 из брифа}».** {выполнено / частично / не выполнено / неприменимо.} {Одно-два предложения обычным языком: что подтверждено, какие доказательства, что осталось.}
- **«{цитата пункта 2 из брифа}».** {статус.} {комментарий.}
- **«{цитата пункта из expectations (уточнение брифа)}».** {статус.} {комментарий.}
- _(и так по каждому пункту в исходном порядке)_

## Артефакты задачи

{Что подтверждено или закреплено по итогам прохода: ссылки на отчёты, изменённые файлы, обновлённые контракты. Свободная проза + bullet.}

## Следующие шаги

{Либо «всё закрыто», либо bullet/проза. Указывать конкретные команды `/dr-*` или операторские действия (включая `/dr-archive`).}

---

## Дополнительно для аудита

### Step-by-step verdicts

<!-- gate:literal -->
| Step | Verdict | Notes |
|---|---|---|
| 1. Re-validate vs PRD/task | {compliant|notes|non-compliant} | {summary} |
| 2. Simplify code | {compliant|notes|non-compliant} | {summary} |
| 3. Check references | {compliant|notes|non-compliant} | {summary} |
| 4. Coverage | {compliant|notes|non-compliant} | {summary} |
| 5. Lint | {compliant|notes|non-compliant} | {summary} |
| 6. Tests | {compliant|notes|non-compliant} | {summary} |
| 7. Final verdict | {COMPLIANT|COMPLIANT_WITH_NOTES|NON-COMPLIANT} | {summary} |
<!-- /gate:literal -->

### Remaining risks

{Список рисков, которые остались открытыми после compliance-прохода. Если пусто — одна строка «нет открытых рисков».}

### Related

- Task: `datarim/tasks/{TASK-ID}-task-description.md`
- PRD: (path or none)
- Plan: (path or none)
- QA report: (path or none)
- Archive: (path or none — заполняется после `/dr-archive`)
