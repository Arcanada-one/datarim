---
id: dr-orchestrate
title: /dr-orchestrate — Self-Driving Datarim Pipeline (Phase 1)
description: "Tmux-based pipeline runner. Phase 1: lean rule-based, bash-only."
usage: |
  dr-orchestrate run
  dr-orchestrate run --dry-run
options:
  --dry-run: "Log decisions without executing"
  --interval: "Poll cycle interval in seconds (default: 5)"
autonomy: L1
phase: 1
plugin: dr-orchestrate
task: TUNE-0164
---

# /dr-orchestrate

Phase 1 — Lean tmux Runner.

Базовый цикл:

1. `tmux capture-pane -p -t <pane>` — снимает текущий буфер pane.
2. `semantic_parser.sh parse` — rule-based stub возвращает `{command, confidence, source}`.
3. Решение логгируется в `audit_sink.sh emit` (JSONL, `~/.local/share/datarim-orchestrate/audit-YYYY-MM-DD.jsonl`).
4. Любой `tmux send-keys` проходит security-floor: whitelist → escape-block → cooldown → fail-closed.

Подробнее: `plugins/dr-orchestrate/README.md` и `prd/PRD-TUNE-0104-orchestrate-plugin.md`.
