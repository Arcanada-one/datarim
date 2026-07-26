---
id: TUNE-0517
title: Vendor-default model and latest CLI-agent policy
status: archived
completed_date: 2026-07-26
complexity: L2
type: framework
project: Datarim
related: []
archive_doc: documentation/archive/framework/archive-TUNE-0517.md
verification_outcome:
  caught_by_verify: 3
  missed_by_verify: 0
  false_positive: 0
  n_a: false
  dogfood_window: "TUNE-0517-2026-07"
---

# Архив: TUNE-0517 — Vendor-default model and latest CLI-agent policy

## Начальная задача

Закрепить vendor-default model and effort policy, добавить permission-aware
CLI guidance и optional fail-open version awareness, сохранив Class A boundary.

## Как решили

- **«Пройти полный lifecycle в собственном worktree и signed branch».** выполнено. Init, plan, implementation, QA, compliance и archive сохранены отдельными подписанными push checkpoints.
- **«Сначала добавить one-liner в Pending backlog».** выполнено. Запись была добавлена, затем удалена при переводе задачи в active state согласно thin backlog contract.
- **«Следовать current vendor defaults и не выдумывать IDs».** выполнено. Конфигурация хранит vendor-default intent, а adapter обязан опустить model override.
- **«Сделать CLI policy permission-aware».** выполнено. Upgrade разрешён только там, где среда позволяет установку; иначе guidance остаётся advisory.
- **«Version awareness должна быть fail-open».** выполнено. Probe opt-in, ограничен timeout и не влияет на selection result.
- **«Не менять routing или exit codes».** выполнено. Existing order, availability checks и failure behavior сохранены.
- **«Проверить public shipped-surface hygiene».** выполнено. Added shipped lines проходят ASCII и prohibited-literal scans.
- **«Vendor-default policy is canonical and cross-linked (уточнение брифа)».** выполнено. Canonical section и consumer pointers покрыты focused tests.
- **«Latest CLI guidance is permission-aware (уточнение брифа)».** выполнено. Advisory semantics подтверждены policy test.
- **«Fleet awareness is fail-open and autonomous choice pre-resolved (уточнение брифа)».** выполнено. Failure и hung-command runtime tests проходят.
- **«Configuration is safely de-pinned and hygiene gates pass (уточнение брифа)».** выполнено. YAML, validation, lint, full tests, signatures и remote state проверены.

## Артефакты задачи

- `skills/datarim-system/model-assignment.md`
- `config/model-tiers.yaml`
- `CLAUDE.md`
- `commands/dr-orchestrate.md`
- `skills/autonomous-mode/SKILL.md`
- `plugins/dr-orchestrate/scripts/subagent_resolver.sh`
- `tests/tune-0517-vendor-default-policy.bats`
- `datarim/qa/qa-report-TUNE-0517.md`
- `datarim/reports/compliance-report-TUNE-0517.md`
- `datarim/reflection/reflection-TUNE-0517.md`

## Следующие шаги

всё закрыто

---

## Дополнительно для аудита

### verification_outcome

- caught_by_verify: 3
- missed_by_verify: 0
- false_positive: 0
- n_a: false
- dogfood_window: TUNE-0517-2026-07

### Acceptance Criteria

<!-- gate:literal -->
| AC | Status | Evidence |
|---|---|---|
| Canonical vendor-default policy | pass | policy section and focused Bats |
| Permission-aware CLI guidance | pass | policy assertion |
| Fail-open version awareness | pass | failure and timeout runtime tests |
| Autonomous pre-resolution | pass | autonomous-mode assertion |
| De-pinned tier semantics | pass | YAML parse and tier assertions |
| Consumer cross-links | pass | CLAUDE and orchestration assertions |
| Presence regression coverage | pass | focused suite 20/20 |
| Lifecycle and hygiene | pass | canonical suite 2,086/2,086; validation and lint pass |
<!-- /gate:literal -->

### Verification

- `bats tests` — 2,086/2,086 passed.
- Focused policy plus selector suites — 20/20 passed.
- Public-surface lint — 17/17 passed.
- `./validate.sh`, repository-wide ShellCheck, `bash -n`, and YAML parse passed.
- Added shipped lines contain no non-ASCII or prohibited operator literals.
- Pre-archive shared-tree, unpushed-commit, expectations, anti-deferral,
  reflection-freshness, and version-consistency gates passed.
- A non-blocking stale-runtime reminder advises updating other installations.

### Lessons Learned

- Semantic vendor-default intent is safer than guessed model identifiers.
- Fail-open diagnostics still need a strict timeout.
- Multi-assertion Bats tests need explicit failure propagation.

### Operator Handoff

всё закрыто

### Related

- Parent PRD: none
- Plan: `datarim/plans/TUNE-0517-plan.md`
- QA: `datarim/qa/qa-report-TUNE-0517.md`
- Compliance: `datarim/reports/compliance-report-TUNE-0517.md`
- Reflection: `datarim/reflection/reflection-TUNE-0517.md`
- Follow-ups: none
