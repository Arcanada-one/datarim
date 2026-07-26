---
task_id: TUNE-0516
artifact: expectations
schema_version: 2
captured_at: 2026-07-26
captured_by: /dr-init
status: canonical
agent: planner
parent_init_task: TUNE-0516-init-task.md
---

# TUNE-0516 — Ожидания оператора

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
> Валидатор: `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task TUNE-0516`.

## Ожидания

- **1. В backlog-and-routing.md добавлен инвариант параллельной оркестрации (одна сессия на задачу, параллельность по умолчанию, не сериализовать) и перекрёстные ссылки.**
  - wish_id: parallel-orchestration-invariant
  - Что хочу проверить: В skills/datarim-system/backlog-and-routing.md появилась новая подсекция «Parallel orchestration is the default», в которой заявлено, что каждая задача выполняется в собственной изолированной сессии (отдельный ворктри + ветка), параллельные сессии нормальны, сериализация задач не допускается, а координация требуется только при пересечении веток или файлов. Также из commands/dr-orchestrate.md и commands/dr-auto.md проставлены перекрёстные ссылки на эту подсекцию. Опциональный пример помечен как «non-normative» и использует заполнители.
  - Как проверить (success criterion): `grep -q "Parallel orchestration is the default" skills/datarim-system/backlog-and-routing.md`; в commands/dr-orchestrate.md и commands/dr-auto.md есть ссылка на данный раздел; в backlog-and-routing.md присутствует фраза «example — adapt to your infrastructure» и пример с placeholder-именами.
  - Связанный AC из PRD: —
  - evidence_type: static
  - #### История статусов
    - 2026-07-26T15:00:00+03:00 / 15:00 MSK · /dr-init · pending → pending · reason: пункт создан при формировании контракта ожиданий
    - 2026-07-26T09:06:00Z / 09:06 UTC · /dr-qa · pending → met · reason: canonical rule, isolation boundary, cross-links, and placeholder example verified by focused bats and diff review
  - #### Текущий статус
    - met

- **2. Добавлено правило немедленного коммита-и-пуша изменений статусов задач с bats‑регрессией.**
  - wish_id: commit-push-status-immediately
  - Что хочу проверить: В command-and-archive-rules.md (или рядом с ним) появилось правило «Persist status changes immediately»: при смене статуса в отслеживаемом операционном файле (backlog/tasks/activeContext) коммит и пуш выполняются сразу; не накапливаются незакоммиченные переключения; затрагиваются только записи статусов, не промежуточный код. Существует bats‑тест, проверяющий присутствие этого правила в файле.
  - Как проверить (success criterion): `grep -q "Persist status changes immediately" skills/datarim-system/command-and-archive-rules.md`; запуск bats-теста (ожидается заданное присутствие) завершается успешно; тест зафиксирован в репозитории (например, `tests/tune-0516-commit-push.bats` или аналогичное имя).
  - Связанный AC из PRD: —
  - evidence_type: static
  - #### История статусов
    - 2026-07-26T15:00:00+03:00 / 15:00 MSK · /dr-init · pending → pending · reason: пункт создан при формировании контракта ожиданий
    - 2026-07-26T09:06:00Z / 09:06 UTC · /dr-qa · pending → met · reason: prompt commit-and-push rule and WIP boundary verified by focused bats; task checkpoints are signed and pushed
  - #### Текущий статус
    - met

- **3. Документация маркера /dr-auto в CLAUDE.md исправлена на схему per‑task.**
  - wish_id: claude-auto-marker-fix
  - Что хочу проверить: Описание команды /dr-auto в CLAUDE.md больше не упоминает устаревший общий маркер `datarim/.auto-mode-active`; вместо него используется привязка к задаче `datarim/.auto/<TASK-ID>.mode`, соответствующая skills/autonomous-mode/SKILL.md:18.
  - Как проверить (success criterion): `grep -r "datarim/.auto-mode-active" CLAUDE.md` возвращает ноль совпадений; `grep -q "datarim/.auto/<TASK-ID>.mode" CLAUDE.md` находит корректное описание.
  - Связанный AC из PRD: —
  - evidence_type: static
  - #### История статусов
    - 2026-07-26T15:00:00+03:00 / 15:00 MSK · /dr-init · pending → pending · reason: пункт создан при формировании контракта ожиданий
    - 2026-07-26T09:06:00Z / 09:06 UTC · /dr-qa · pending → met · reason: CLAUDE.md names the per-task marker and the legacy marker is absent
  - #### Текущий статус
    - met

- **4. Финальный deliverable — только ASCII на экспортируемой поверхности, без операторских имён, и пройдены все гейты пайплайна (lint, bats, shellcheck, подписанный коммит, архив).**
  - wish_id: shipped-surface-compliance
  - Что хочу проверить: Все изменённые в рамках задачи файлы содержат только 7‑битные символы; ни в одном экспортируемом файле не встречаются имена и строки Arcanada, DEVS, dev-ai, Aether, tailscale, space.yml и им подобные; lint, bats, shellcheck завершаются успешно; финальный коммит имеет цифровую подпись; задача заархивирована в datarim/archive/.
  - Как проверить (success criterion): `grep -rP '[^\x00-\x7F]' --include='*.md' --include='*.sh'` в репозитории не выдаёт результатов среди changed файлов; `grep -rE 'Arcanada|DEVS|dev-ai|Aether|tailscale|space\.yml'` — ноль попаданий в shipped‑файлах; вывод `check-expectations-checklist.sh --task TUNE-0516` и стандартные прогоны lint/bats/shellcheck показывают PASS; `git log --show-signature -1` содержит Valid; наличие артефакта в `datarim/archive/TUNE-0516-*.md`.
  - Связанный AC из PRD: —
  - evidence_type: empirical
  - #### История статусов
    - 2026-07-26T15:00:00+03:00 / 15:00 MSK · /dr-init · pending → pending · reason: пункт создан при формировании контракта ожиданий
    - 2026-07-26T09:06:00Z / 09:06 UTC · /dr-qa · pending → pending · reason: ASCII, literal, validation, full bats, shellcheck, signing, and push evidence pass; archive remains the downstream lifecycle stage
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

> Дополнения добавляются хронологически. Каждое — отдельная подпись
> (`### <ISO 8601 timestamp> — amendment by <author>`), без таблиц.

_(пусто на момент создания)_
