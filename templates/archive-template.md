---
id: {TASK-ID}
title: {short title, ≤80 chars}
status: archived
completed_date: {YYYY-MM-DD}
complexity: L{1-4}
type: {framework|infra|content|bugfix|...}
project: {Datarim|Arcanada|...}
related: []
archive_doc: documentation/archive/{subdir}/archive-{TASK-ID}.md
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 0
  false_positive: 0
  n_a: false
  dogfood_window: "{window-id}"
---
<!--
verification_outcome field semantics:
- caught_by_verify: integer count of high/medium gaps caught BEFORE /dr-archive
- missed_by_verify: integer count of gaps that escaped /dr-verify and required post-archive followup
- false_positive: integer count of findings flagged by /dr-verify that were triaged as not real
- n_a: boolean, true when /dr-verify was NOT run; when true, the three counts above MUST be 0
- dogfood_window: active prospective-measurement window identifier; grouping key for measure-prospective-rate.sh
Канонический контракт — skills/self-verification/SKILL.md § Findings Schema.
-->

# Архив: {TASK-ID} — {Title}

## Начальная задача

{Одно предложение обычным языком, что требовалось сделать. Источник — `tasks/{TASK-ID}-init-task.md` § Operator brief (verbatim), сжатое до одной фразы.}

## Как решили

{Маркированный список, по одному пункту на каждый bullet операторского брифа из `tasks/{TASK-ID}-init-task.md` в исходном порядке. Если есть `tasks/{TASK-ID}-expectations.md` — каждый пункт § Ожидания добавляется в тот же список с пометкой «(уточнение брифа)». Без таблиц, без вложенных bullet. Банлист `skills/human-summary/banlist.txt` применяется к комментариям.}

- **«{цитата пункта 1 из брифа}».** {выполнено / частично / не выполнено / неприменимо.} {Одно-два предложения обычным языком: что сделано, какие доказательства, что осталось.}
- **«{цитата пункта 2 из брифа}».** {статус.} {комментарий.}
- **«{цитата пункта из expectations (уточнение брифа)}».** {статус.} {комментарий.}
- _(и так по каждому пункту в исходном порядке)_

## Артефакты задачи

{Что появилось или изменилось. Свободная проза + bullet. Файлы — относительные пути. Без verdict-таблиц.}

## Следующие шаги

{Либо «всё закрыто», либо bullet/проза. Указывать конкретные команды `/dr-*` или операторские действия.}

---

## Дополнительно для аудита

### verification_outcome

{Дублирует YAML frontmatter в человеческом представлении: по одному bullet на каждый счётчик (`caught_by_verify`, `missed_by_verify`, `false_positive`, `n_a`) + `dogfood_window`.}

### Acceptance Criteria

| AC | Status | Evidence |
|---|---|---|
| AC-1: {description} | {pass/fail/partial} | {link or summary} |
| AC-2: {description} | {pass/fail/partial} | {link or summary} |

### Lessons Learned

{Короткая выжимка ≤3 bullet. Полный текст — `reflection-{ID}.md`.}

### Operator Handoff

{Любые остаточные следы, отложенные улучшения или операторские шаги для следующего исполнителя. Если пусто — одна строка «всё закрыто».}

### Related

- Parent PRD: (path or none)
- Plan: (path or none)
- Reflection: (path or none)
- Follow-ups: (task IDs or none)
