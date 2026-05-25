---
name: autonomous-mode
description: Question Suppression Ladder (5 levels) + L1 Inline Resolution Rule + Hard-gated Action Boundary. Активируется через DATARIM_AUTO_MODE=1 + datarim/.auto-mode-active marker под /dr-auto.
model: opus
runtime: [claude, codex]
current_aal: 2
target_aal: 2
---

# Autonomous Mode — Question Suppression + L1 Inline + Hard-gated Boundary

Этот skill активирует существующие mandates (`documentation/mandates/autonomous-agents.md` FB-1..8, `feedback_l1_proposals_close_in_cycle`, `feedback_autonomous_ops`) как **default-on** в пределах active `/dr-auto` cycle. Не вводит новых правил — только меняет default с «conditional activation» на «always active while mode is on».

## When this skill is active

Active iff **все три условия** соблюдены:

1. `DATARIM_AUTO_MODE=1` установлен в окружении процесса.
2. File marker `datarim/.auto-mode-active` существует и читается как YAML.
3. Значение `task_id` в marker совпадает с current TASK-ID (шаблон `^[A-Z]{2,10}-[0-9]{4}$`).

**Mismatch** (env var set, но marker отсутствует ИЛИ marker содержит другой TASK-ID) → emit single-line warning: `⚠ auto-mode: DATARIM_AUTO_MODE=1 but marker absent/mismatch → treat as non-auto (fail-safe)`. Дальнейшее выполнение как non-auto.

**Marker file structure** (`datarim/.auto-mode-active`):
```yaml
task_id: TUNE-XXXX
activated_at: 2026-05-24T12:00:00Z
activated_by: /dr-auto
mode: continue|bootstrap
```

**24h TTL.** Marker created > 24h ago → silent purge (агент удаляет файл или игнорирует его). Только `/dr-auto` re-создаёт.

## Question Suppression Ladder

Перед каждым `AskUserQuestion` (или эквивалентным operator prompt — текстовым "What do you think?" "Как лучше?") агент **MUST** пройти уровни L1→L4 последовательно. Останавливается на **первом**, который даёт **unambiguous** answer. Только если L1-L4 все не дали однозначного ответа → L5 (operator).

| L | Источник | Когда применимо | Cost | Failure mode → escalate to |
|---|----------|-----------------|------|---------------------------|
| 1 | **Codebase grep / file read** | Технический вопрос про текущий код, конфиг, схему, версии, зависимости, структуру проекта | <1s | Множественные кандидаты (≥2) без tie-breaker → L2 |
| 2 | **Runtime probe** (`curl localhost:3200/healthz`, `docker ps`, `git log -1`, `gh run list`, `vault kv get`, `kubectl get pods`) | Состояние сервиса, БД, network, CI, deployed secrets, container health | <5s | Probe failed / no signal / timeout → L3 |
| 3 | **MEMORY.md feedback lookup** | Operator preferences, prior decisions, gotchas, policy — `grep -r feedback_` в `MEMORY.md` | <2s | Не найдено / противоречие → L4 |
| 4 | **Coworker delegation** (`coworker ask --paths <list> --question "<question>"`) | Bulk-context: docs across repos, multiple large files, external LLM reasoning на >10k tokens | <30s | External LLM не дал unambiguous answer (или says "unknown") → L5 |
| 5 | **Operator ask** (`AskUserQuestion`) | True ambiguity, hard-gated bypass, business strategy | минута+ | Operator answer = source-of-truth; log via `append-init-task-qa.sh --decided-by operator` |

### Ambiguity Definition

≥2 plausible candidate answers на **одном уровне** без deterministic tie-breaker (например, два package.json с разными version полями) → **escalate to next level**. Если tie-breaker возможен (например, grep по explicit path вместо wildcard) — применить tie-breaker, не escalate.

### Business-strategy questions (narrow mode)

Вопросы, требующие business knowledge, **сразу L5**, без попытки L1-L4:

- «Продаём ли мы X на рынке Y?»
- «Кто является paying customer для этого функционала?»
- «Какая pricing политика для legacy tier?»
- «Legal stance на GDPR compliance для этого DPA?»
- Any question где answer = operator intent, а не факт codebase/runtime.

Не применять safe-default. Флаг «assumed default — confirm at archive» — отдельный FU после ≥3 dogfood циклов. Wide-mode опционал — отдельный backlog item, не текущий contract.

## L1 Inline Resolution Rule

Применяется во **всех** стадиях `/dr-auto` cycle: `init`, `prd`, `plan`, `do`, `qa`, `compliance`, `archive` — не только `/dr-archive` reflection.

### Decision tree

```
discovered gap / improvement opportunity mid-cycle
  ↓
classify by scope (a), contract impact (b), hard-gated check (c):
  
  (a) scope of change:
      - single file edit → check (b)
      - multi-file → L2+, backlog

  (b) contract impact:
      - ≤50 LoC, no API/schema/contract/mandate change → L1 Class A
      - API schema change / operating-model shift / PRD change → L2+ или Class B, backlog
  
  (c) hard-gated check (overrides a+b):
      - matches autonomous-agents.md:30-32 list → HARD, always operator-escalate
      - cross-project boundary (repo outside task's project scope) → HARD
      - neither → proceed with (a)→(b) classification

  resolution:
      L1 Class A → fix INLINE в текущем /dr-do scope; log в auto-inline-log.md
      L2+ или Class B → create backlog item with Source: discovered-during-auto-{TASK-ID}
      HARD → emit operator prompt через Ladder L5; do not auto-execute
```

### Inline-log contract

File: `datarim/tasks/{TASK-ID}-auto-inline-log.md` — append-only, populated during `/dr-do`. Each entry:

```markdown
### <ISO-ts> · inline-gap-resolved

- **What:** <1-line description of gap>
- **Files touched:** <list of file paths>
- **LoC delta:** <±N total>
- **Classification rationale:** <почему L1 + Class A: single file, ≤50 LoC, no contract change, not hard-gated>
```

Consumed at `/dr-archive` Step 0.5 (pre-reflection): inline-log surfaces as «Inline-resolved gaps» section в archive doc. Если archive Step 0.5 находит unresolved entries → warning: «N inline gaps не залогированы в auto-inline-log.md — check /dr-do completion».

## Hard-gated Action Boundary

**Verbatim** из `documentation/mandates/autonomous-agents.md:30-32` (не цитировать по памяти, не перефразировать):

> Production deploys, secret rotation, irreversible DB operations (DROP / TRUNCATE without backup), public communications (Telegram channel posts, blog posts, social media), finance / legal actions, force-push to `main`/`master`, deletion of git history, and any action affecting > 1 human user.

Под `/dr-auto` эти действия **никогда не auto-execute**:

1. Агент распознаёт action как hard-gated (по verbatim списку или cross-project boundary).
2. Escalate через Ladder L5: `AskUserQuestion` с explicit указанием «This action is hard-gated per autonomous-agents.md:32. Operator approval required before execution.»
3. Operator response logged через `dev-tools/append-init-task-qa.sh --decided-by operator --question "<question text>" --answer "<operator response>"`.

**Дополнительно (cross-project boundary):** Действия, затрагивающие репозитории за пределами TASK's project scope (определяется по Task Prefix Registry — `Arcanada/CLAUDE.md` или `documentation/architecture/task-prefix-registry.md`), также считаются hard-gated. Example: задача с prefix `SUP-` пытается edit `Projects/Verdicus/` → hard-gated.

**Не считать hard-gated:** infra-side действия на Arcanada-owned resources (SSH, docker restart, git push на feature branch, vault read, Cloudflare API чтение) — разрешены per `feedback_autonomous_ops`.

## Failure modes

- **Env-var leak**: parent shell сохранил `DATARIM_AUTO_MODE=1` после `/clear`. **Mitigation:** mismatch detection (env var set, marker absent) → silent treat as non-auto + warning. Marker TTL 24h предотвращает stale leaks.
- **Marker stale**: marker остался от crashed session. **Mitigation:** marker TTL 24h; non-current marker → silent purge before activation.
- **Ladder false-confident**: L1-L4 нашли answer, но он неверный (wrong grep result). **Mitigation:** ambiguity rule — ≥2 candidates → escalate. Single candidate считается valid; audit trail через Q&A append-log позволяет operator откатить.
- **Coworker context leak (L4)**: bulk-read paths случайно включают credentials. **Mitigation:** reuse существующий coworker safety contract — пути из `~/arcanada/config/credentials/` excluded. Ladder L4 invokes `coworker ask` с explicit path list, не wildcard.
- **Cross-project unauthorized writes**: агент edit'ит repo за пределами task's project scope. **Mitigation:** hard-gated cross-project boundary; runtime check before file write.
- **L1 Inline Rule mis-classification**: L2 action классифицирован как L1 → silent contract drift. **Mitigation:** «when in doubt → classify up» в decision tree. Auto-inline-log mandatory для audit.
- **Pre-archive workspace gate over-strict on foreign untracked files**: `scripts/pre-archive-check.sh` treats parallel-session untracked files (foreign social posts, sibling-project site, framework test fixtures под другими TASK-ID) как `unattributed = default-deny` и блокирует archive. **Mitigation:** для own files с foreign-mixed diff — HEAD-restore + reapply technique (restore HEAD version, apply only own changes, re-stage); для truly foreign untracked artefacts — manual override (skip script gate) + documented entry в archive § Operator Handoff с file list. Long-term fix tracked as Class B backlog item.

## How commands consume this skill

Каждая из 7 pipeline-команд (`dr-init`, `dr-prd`, `dr-plan`, `dr-do`, `dr-qa`, `dr-compliance`, `dr-archive`) содержит section `## /dr-auto Mode` после `## Instructions`:

```markdown
## /dr-auto Mode (when DATARIM_AUTO_MODE=1)

When auto-mode is active (env var + matching marker), this command:

1. Consult `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder before any `AskUserQuestion` or equivalent operator prompt.
2. Stage-specific suppression hooks:
   - <stage-specific list: e.g. для /dr-init: skip Discovery Interview round 2 if all questions resolved through L1-L4>
   - <для /dr-do: apply L1 Inline Rule on discovered gaps during execution>
   - <для /dr-archive: consume auto-inline-log.md before reflection>
3. Discovered gaps → apply L1 Inline Rule per `skills/autonomous-mode/SKILL.md`; log в `datarim/tasks/{TASK-ID}-auto-inline-log.md` if resolved inline.
4. Hard-gated actions → escalate to operator через Ladder L5, log through `dev-tools/append-init-task-qa.sh --decided-by operator`.
```

## Related

- `commands/dr-auto.md` (caller — activates this skill and sets env var + marker)
- `documentation/mandates/autonomous-agents.md` (FB-1..8 mandate — source-of-truth for all rules activated here)
- `skills/cta-format/SKILL.md` § Snapshot Emission (terminal step contract at end of each stage)
- `skills/init-task-persistence/SKILL.md` § Q&A round-trip (L5 logging mechanism via `append-init-task-qa.sh`)
- Memory: `feedback_l1_proposals_close_in_cycle` (L1 rule precedent, originally scoped to /dr-archive only)
- Memory: `feedback_autonomous_ops` (infra-side autonomy scope — SSH/Cloudflare/Vault/docker/git on Arcanada resources)