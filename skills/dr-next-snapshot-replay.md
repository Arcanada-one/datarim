---
name: dr-next-snapshot-replay
description: Consumer contract for stage snapshots — /dr-next and /dr-orchestrate read datarim/snapshots/{TASK-ID}.snapshot.md first, emit replay-prompt with CTA + bilingual autonomy reminder + `done before:` body.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Stage-Snapshot Replay (consumer side)

`/dr-next` и `/dr-orchestrate` после Task Resolution читают снапшот **первым** — до task-description, init-task, activeContext, PRD, plan. Если снапшот существует и валиден — собирают replay-промпт по канонической форме и продолжают автономно. Если снапшота нет или он malformed — fallback на legacy-поведение без warning-шума.

## Contract

| Aspect | Value |
|--------|-------|
| Consumer touchpoints | `commands/dr-next.md` § Step 2.5, `plugins/dr-orchestrate/commands/dr-orchestrate.md` § Snapshot-First Resume |
| Snapshot path | `datarim/snapshots/{TASK-ID}.snapshot.md` |
| Validator | `dev-tools/check-stage-snapshot-on-exit.sh --validate-frontmatter --task <ID>` (exit 0 = ok) |
| Fallback policy | snapshot absent OR validator exit ≠ 0 → legacy Read pipeline, **no warning** (V-AC-7) |
| Prompt template | см. § Replay-prompt template ниже |

## Replay-prompt template (canonical, V-AC-6 + V-AC-11)

Когда снапшот валиден, эмитируем именно эту форму, без отсебятины:

```
<recommended-CTA>

ищи способ исследовать все проблемы и ответить на все вопросы самостоятельно. выполняй за оператора все необходимые шаги и требования, которые можешь сделать сам. не создавай FU подзадачи, если они уровня 1, а решай их в этом же цикле до полного решения.
Find a way to investigate all problems and answer all questions yourself. Perform on behalf of the operator every step and requirement you can do yourself. Do not spawn FU sub-tasks for Level-1 work — resolve them in the same cycle to completion.

done before:
<snapshot body>
```

- `<recommended-CTA>` — содержимое `recommended_next` из frontmatter + одна строка purpose, развёрнутая через CTA-heuristic ниже.
- Билингвальный блок (RU primary + EN dub) обязателен в **каждом** replay-промпте — гарантирует исполнение независимо от locale рантайма (Claude Code / Codex CLI / EN-locale агенты).
- `done before:` шапка — литерал; ниже неё точное содержимое body снапшота.

## CTA Selection heuristic (V-AC-12, natural-language guidance)

`recommended_next` из снапшота — hint, эмитированный предыдущей стадией уже корректно по правилам `cta-format.md` § Authoring Rules. Heuristic документирует **rationale**, по которому эту опцию следует предпочесть, а не пересчитывает её. Если у оператора есть основания выбрать другую опцию из `options[]`, он явно вводит её — replay-промпт показывает рекомендованную, но не блокирует override.

Принцип: **максимальное приращение качества решения**. Для L3+ задач с малым числом пройденных проверок предпочитать verification-команды (`/dr-verify`, `/dr-qa`, `/dr-design`) перед `/dr-do`. Когда проверки насыщены — переходить к реализации или archiving.

### Example 1 — L3+ после `/dr-plan`, мало проверок → `/dr-verify`

Снапшот: `recommended_next: /dr-verify`, `options:`
- `/dr-do <TASK-ID> | TDD implementation`
- `/dr-design <TASK-ID> | ratify Vault relativePath`
- `/dr-qa <TASK-ID> | pre-implementation coverage`
- `/dr-verify <TASK-ID> | tri-layer план verification`
- `/dr-status | escape hatch`

Heuristic выбирает `/dr-verify` — план только-только завершён, security-review/threat-model ещё не cross-checked независимым slой-ом. Verification дешевле, чем откатывать `/dr-do`, если найдут drift. Rationale: <TASK-ID> — L3 security-critical задача с 21 V-AC; cost-вердикта верификации (Layer 1 deterministic + Layer 2 cross-model + Layer 3 native dispatch) намного ниже, чем откат бутстрапа на PROD.

### Example 2 — L3+ насыщен проверками (plan + design + verify done) → `/dr-do`

Снапшот: `recommended_next: /dr-do`, `options:`
- `/dr-do <TASK-ID> | TDD implementation`
- `/dr-qa <TASK-ID> | redo coverage check`
- `/dr-status | escape hatch`

Heuristic выбирает `/dr-do` напрямую. Rationale: accumulated evidence (план + design + tri-layer verify all green) достаточно для уверенного implementation pass. Повторный `/dr-qa` — diminishing returns; `/dr-status` — escape hatch для нестандартных решений оператора.

### Example 3 — L1/L2 после `/dr-do` → `/dr-archive`

Снапшот: `recommended_next: /dr-archive`, `options:`
- `/dr-archive <TASK-ID> | finalise + archive doc`
- `/dr-qa <TASK-ID> | optional re-check`
- `/dr-status | escape hatch`

Heuristic выбирает `/dr-archive`. Rationale: L1/L2 после `/dr-do` — по `cta-format.md` § Authoring Rules primary = `/dr-archive`. Реализация уже завершена; archive фиксирует выводы и освобождает activeContext. Override — только если на `/dr-do` всплыли open questions, оправдывающие revisit.

## Implementation outline

```
1. Resolve TASK-ID per Task Resolution Rule.
2. snapshot_path = "$REPO_ROOT/datarim/snapshots/${TASK_ID}.snapshot.md"
3. if check-stage-snapshot-on-exit.sh --validate-frontmatter --task "$TASK_ID" → exit 0:
       read snapshot body + frontmatter
       emit replay prompt per § Replay-prompt template
       STOP downstream Read pipeline — primary context = snapshot
   else:
       silent fallback → legacy Read order (task-description / init-task / activeContext)
```

`/dr-orchestrate` интегрируется через snapshot-first read **до** `subagent_resolver.sh`; `recommended_next` подаётся в resolver как `--hint <command>`. Resolver всё ещё может вернуть иной command — snapshot это hint, не constraint.

## Related

- `skills/stage-snapshot-writer.md` — producer-сторона
- `skills/cta-format.md` — формат CTA-блока, который попадает в `<recommended-CTA>`
- `dev-tools/check-stage-snapshot-on-exit.sh` — обязательный validator перед эмиссией промпта
- `commands/dr-next.md` § Step 2.5 — consumer-точка
- `plugins/dr-orchestrate/commands/dr-orchestrate.md` § Snapshot-First Resume — orchestrator-точка
