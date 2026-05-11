<!-- gate:history-allowed -->
---
id: dr-orchestrate
title: /dr-orchestrate — Self-Driving Datarim Pipeline (Phase 2)
description: "Tmux-based pipeline runner. Phase 2 adds multi-backend subagent inference for unknown prompts (autonomy L1→L2)."
usage: |
  dr-orchestrate run
  dr-orchestrate run --dry-run
  dr-orchestrate run --unknown-prompt [text]
options:
  --dry-run: "Log decisions without executing"
  --interval: "Poll cycle interval in seconds (default: 5)"
  --unknown-prompt: "Resolve a parser-miss prompt via the subagent inference chain"
autonomy: L2
phase: 2
plugin: dr-orchestrate
task: TUNE-0165
---
<!-- /gate:history-allowed -->

# /dr-orchestrate

Phase 2 — Subagent Inference Layer (v2.4.0).

## Цикл

1. `tmux capture-pane -p -t <pane>` — снимает текущий буфер.
2. `semantic_parser.sh parse` — rule-based pass возвращает `{command, confidence, source}`.
3. **Hit (confidence > 0)** — Phase 1 path: лог `make_event` v1, JSONL append.
4. **Miss (confidence == 0)** — Phase 2 path:
   - `subagent_resolver.sh resolve` — multi-backend chain (coworker → claude → codex), 15s per backend, lenient JSON parse, FD-3 close.
   - Confidence threshold gate (default `0.80`):
     - Pass → audit `outcome: resolved` (schema v2); decision-cooldown 60s enforces single autonomous decision per pane per minute.
     - Fail / chain_exhausted → `escalation_backend.sh emit` (mock JSONL по умолчанию; `dev-bot` backend остаётся stub до появления реального consumer-сервиса) + audit `outcome: escalated`.
5. Любой `tmux send-keys` всё так же проходит security-floor: whitelist → escape-block → micro-cooldown (500ms) + decision-cooldown (60s) → fail-closed.

## Конфигурация (user-config.yaml)

```yaml
subagent:
  fallback_chain: ["coworker-deepseek", "claude", "codex"]
  timeout_s: 15
  confidence_threshold: 0.80
escalation:
  backend: "mock"
  mock_log: ~/.local/share/dr-orchestrate/escalation.jsonl
```

## Аудит (schema v2)

- `make_event_v2` — добавляет поля `schema_version: 2`, `confidence`, `subagent_model`, `backend_used`, `escalation_backend`, `stage` (parse / resolve / escalate), `outcome` (matched / resolved / escalated / blocked_decision_cooldown), `reason` (grep-redacted).
- Phase 1 v1 события сохраняются для rule-hit пути — обратная совместимость.
- `matched_text_hash` (sha256) — V-AC-12 инвариант сохраняется; raw pane text никогда не попадает в лог.

## Security Floor (расширения Phase 2)

- `flock -n` обёртка вокруг cooldown read-write на Linux хостах (V-AC-21 race-safe).
- macOS fallback: one-time WARN, non-atomic semantics (Phase 1 поведение).
- Decision-cooldown (60s) — отдельный гейт для autonomous decisions через resolver path.
- Reason-redaction: `password=`, `token=`, `secret=`, `credential=`, `api_key=` элидятся в `<REDACTED>` до записи.

<!-- gate:example-only -->

## CLI examples

```bash
# default Phase 2 cycle: parse → (rule-hit | resolver → autonomous-or-escalate)
dr-orchestrate run --pane "%5"

# dry-run отображает baseline без mutation
dr-orchestrate run --dry-run

# manual resolver invocation with inline text
dr-orchestrate run --unknown-prompt "operator paste: > /dr-prd strategy gate"
```

Inspect audit:

```bash
tail -1 ~/.local/share/datarim-orchestrate/audit-$(date -u +%Y-%m-%d).jsonl | jq .
```

<!-- /gate:example-only -->

## Referenced

- Phase 2 PRD, plan, and reflection live under `datarim/prd/`, `datarim/plans/`, and `documentation/archive/framework/`.
- Plugin README: `plugins/dr-orchestrate/README.md`
- Resolver agent: `plugins/dr-orchestrate/agents/dr-orchestrate-resolver.md`
