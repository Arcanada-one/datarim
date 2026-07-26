---
task_id: TUNE-0517
date: 2026-07-26
verdict: COMPLIANT
scope: Class A framework policy and fail-open CLI version awareness
---

# Compliance-отчёт: TUNE-0517 — Vendor-default model and latest CLI-agent policy

## Начальная задача

Закрепить vendor-default semantics и permission-aware CLI guidance без
изменения маршрутизации, кодов выхода или операторской специфики.

## Как решили

- **«Выполнить полный lifecycle на собственной signed branch».** выполнено. Все стадии зафиксированы отдельными подписанными коммитами и отправлены в remote branch.
- **«Использовать vendor-default semantics и не выдумывать model IDs».** выполнено. Tier configuration хранит intent и требует от adapter не передавать model override.
- **«Сохранить Class A advisory-only boundary».** выполнено. Routing order, availability criteria и exit codes не изменены.
- **«Version awareness должна быть fail-open».** выполнено. Opt-in probe ограничен timeout, а любой failure игнорируется.
- **«Проверить shipped-surface hygiene».** выполнено. Added shipped lines проходят ASCII и prohibited-literal scans.
- **«Vendor-default policy is canonical and cross-linked (уточнение брифа)».** выполнено. Canonical policy и consumer pointers покрыты Bats.
- **«Latest CLI guidance is permission-aware (уточнение брифа)».** выполнено. Policy требует upgrade только при наличии разрешения.
- **«Fleet awareness is fail-open (уточнение брифа)».** выполнено. Runtime tests покрывают failure и hung command.
- **«Configuration is safely de-pinned (уточнение брифа)».** выполнено. YAML parse, validation, full canonical tests и signing checks успешны.

## Артефакты задачи

- Canonical policy: `skills/datarim-system/model-assignment.md`.
- Declarative tier intent: `config/model-tiers.yaml`.
- Fail-open probe: `plugins/dr-orchestrate/scripts/subagent_resolver.sh`.
- Regression suite: `tests/tune-0517-vendor-default-policy.bats`.
- QA evidence: `datarim/qa/qa-report-TUNE-0517.md`.

## Следующие шаги

Всё закрыто; следующий шаг — `/dr-archive TUNE-0517`.

---

## Дополнительно для аудита

### Step-by-step verdicts

<!-- gate:literal -->
| Step | Verdict | Notes |
|---|---|---|
| 1. Re-validate vs PRD/task | compliant | All eight task ACs are satisfied. |
| 2. Simplify code | compliant | Helper is small, isolated, and reuses the existing timeout primitive. |
| 3. Check references | compliant | Canonical and consumer links resolve; dangling tier reference was removed. |
| 4. Coverage | compliant | Focused policy and selector suite passed 20/20, including failure and hang paths. |
| 5. Lint | compliant | Bash syntax, ShellCheck, YAML parse, validation, and hygiene scans passed. |
| 6. Tests | compliant | Canonical suite passed 2,086/2,086; public-surface lint passed 17/17. |
| 7. Final verdict | COMPLIANT | No unmet expectation or self-deferral finding remains. |
<!-- /gate:literal -->

### Remaining risks

No open task risk. An exploratory noncanonical plugin sweep exposed three
pre-existing GNU `stat` portability failures in unchanged helpers; the
canonical gate is green and TUNE-0517 does not touch those helpers.

### Related

- Task: `datarim/tasks/TUNE-0517-task-description.md`
- PRD: none
- Plan: `datarim/plans/TUNE-0517-plan.md`
- QA report: `datarim/qa/qa-report-TUNE-0517.md`
- Archive: pending

## Operator summary

### What changed

The final hardening pass confirmed that tier configuration expresses
vendor-default intent without naming a model. The fleet selector can emit an
optional version hint, but that probe cannot participate in selection.

### What was verified

Focused runtime tests passed 20/20, the complete canonical suite passed
2,086/2,086, and validation, ShellCheck, YAML parsing, public-surface lint,
ASCII checks, prohibited-literal checks, signatures, and remote branch state
were checked.

### What did not work

No acceptance criterion failed. The provenance helper required an explicit
re-certification after the mandated QA status-flip commit advanced HEAD; the
re-certified gate passed. Three unrelated exploratory plugin failures remain
baseline evidence, not failures of this task.

### What happens next

Archive will remove the active task state, preserve the audit documents, and
push the final signed branch commit. No deployment or release action is
required.
