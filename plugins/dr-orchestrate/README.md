# dr-orchestrate Plugin — Phase 1 (Lean tmux Runner)

> Class B plugin. Status: Phase 1 (TUNE-0164, Datarim v2.3.0).

## Install

```bash
dr-plugin enable dr-orchestrate
```

## Run

```bash
dr-orchestrate run
dr-orchestrate run --dry-run
```

Опционально перед запуском скопировать `user-config.template.yaml` → `user-config.yaml`,
выставить `chmod 600`, заполнить ключи. Default `key_injection: false` — без ручного
включения плагин не будет посылать send-keys.

## Autonomy Levels

- **Phase 1 (TUNE-0164)** → L1 (Manual cycle, rule-based confidence).
- Phase 2 (TUNE-0165) → L2 (Subagent inference + Telegram bridge).
- Phase 3 (TUNE-0166) → L4 (Auto-learning rules, Y/N callback, 24h re-validation).

## Security Floor

Перед любым `tmux send-keys` выполняется фиксированный pipeline:

| Layer | Source | Behaviour |
|-------|--------|-----------|
| Whitelist | `[a-zA-Z0-9 _\-./:=@]` | fail-closed |
| Escape block | byte 0x1b | fail-closed (CVE-2019-9535 mitigation) |
| Micro-cooldown | 500 ms / pane | gate per send |
| Decision-cooldown | 60 s / pane | gate per autonomous decision |
| Violation tracker | 5 hits / hour → 1h pane block | persistent state |

Все блокировки и события пишутся в JSONL audit с hash-only `matched_text_hash` —
raw matched text никогда не попадает в лог (V-AC-12).

## Files

- `plugin.yaml` — manifest (schema_version 1).
- `scripts/plugin.sh` — hook dispatcher (`on_cycle`, `on_tune_complete`, `get_autonomy`).
- `scripts/cmd_run.sh` — entry point for `dr-orchestrate run`.
- `scripts/tmux_manager.sh` — session/pane CRUD.
- `scripts/security.sh` — whitelist + escape + cooldown + violation tracker.
- `scripts/secrets_backend.sh` — YAML backend with mode-0600 enforcement.
- `scripts/audit_sink.sh` — JSONL emit + canonical event shape.
- `scripts/semantic_parser.sh` — Phase 1 stub.
- `commands/dr-orchestrate.md` — command surface.
- `tests/*.bats` — V-AC 1-15 coverage.

## Out of Scope (Phase 1)

Telegram bridge, auto-learning, Vault backend, OpsBot audit sink, multi-host SSH,
Docker/K8s orchestration, native Windows. См. TUNE-0165 / TUNE-0166 / AGENT-0017.
