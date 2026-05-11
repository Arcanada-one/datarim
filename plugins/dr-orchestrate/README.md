# dr-orchestrate Plugin — Phase 2 (Subagent Inference)

> Class B plugin. Status: Phase 2 (Datarim v2.4.0).

## Install

```bash
dr-plugin enable dr-orchestrate
```

## Run

```bash
dr-orchestrate run
dr-orchestrate run --dry-run
dr-orchestrate run --unknown-prompt [text]
```

Опционально перед запуском скопировать `user-config.template.yaml` → `user-config.yaml`,
выставить `chmod 600`, заполнить ключи. Default `key_injection: false` — без ручного
включения плагин не будет посылать send-keys.

## Autonomy Levels

- **Phase 1** → L1 (Manual cycle, rule-based confidence).
- **Phase 2** → L2 (Assisted: multi-backend subagent inference + race-safe cooldown + audit v2).
- Phase 3 (planned) → L4 (Auto-learning rules, Y/N callback, 24 h re-validation).

## Subagent Inference (Phase 2)

When the rule-based parser returns `confidence: 0` (parser miss), `cmd_run.sh`
dispatches to `subagent_resolver.sh`, which classifies the pane text via a
configurable fallback chain of AI CLI backends:

| Backend | Invocation | Notes |
|---------|-----------|-------|
| `coworker-deepseek` (default primary) | `coworker ask --provider deepseek --profile code` | OSS coworker CLI; vendor-neutral |
| `claude` | `claude --print --output-format=json` | Wrapper carries `{type, result}`; resolver re-parses `.result` |
| `codex` | `codex exec --output-last-message -` | Best-effort; chain continues on parse fail |

Each backend has a 15 s wall-clock budget (`DR_ORCH_RESOLVER_TIMEOUT_S`), runs
with FD 3 closed (bats-harness compatibility), and is skipped silently when the
binary is absent from `$PATH` (one-time WARN on first miss). Lenient JSON
extraction handles raw bodies, fenced ```` ```json ```` blocks, and prose-
wrapped objects.

The autonomous-vs-escalate decision lives in `cmd_run.sh`, gated on
`subagent.confidence_threshold` (default `0.80`).

## Escalation

Resolver outputs below the confidence threshold (or `chain_exhausted`) route to
`escalation_backend.sh`:

- **mock** (default) — appends a JSONL event to
  `~/.local/share/dr-orchestrate/escalation.jsonl`. Frozen schema; consumer
  contract documented in the task's `tasks/*-fixtures.md` § Escalation-JSONL
  Schema.
- **dev-bot** — stub returning exit 99 with WARN until a real consumer service
  lands.

## Security Floor

Перед любым `tmux send-keys` и перед любым autonomous decision выполняется
фиксированный pipeline:

| Layer | Source | Behaviour |
|-------|--------|-----------|
| Whitelist | `[a-zA-Z0-9 _\-./:=@]` | fail-closed |
<!-- gate:history-allowed -->
| Escape block | byte 0x1b | fail-closed (CVE-2019-9535 mitigation) |
<!-- /gate:history-allowed -->
| Micro-cooldown | 500 ms / pane | gate per send |
| Decision-cooldown | 60 s / pane | gate per autonomous decision (resolver path) |
| Flock-safe lock | `flock -n` per (pane, kind) | Linux only; macOS one-time WARN, non-atomic fallback |
| Violation tracker | 5 hits / hour → 1 h pane block | persistent state |

Все блокировки и события пишутся в JSONL audit. Schema v2 carries
`schema_version: 2`, `confidence`, `subagent_model`, `backend_used`,
`escalation_backend`, `stage`, `outcome`, and a grep-redacted `reason`.
`matched_text_hash` (sha256) preserves the hash-only invariant — raw pane text
never enters the log.

## Backend Install

`coworker` and `claude` should be on `$PATH` of the host that runs the plugin.

```bash
# coworker (OSS)
curl -fsSL https://raw.githubusercontent.com/Arcanada-one/coworker/main/install.sh | bash

# claude CLI — see https://docs.claude.com/en/docs/claude-code
```

The chain falls through silently on missing backends; the resolver still emits
a clean `chain_exhausted` envelope so the escalation path always runs.

## Files

- `plugin.yaml` — manifest (schema_version 1).
- `scripts/plugin.sh` — hook dispatcher (`on_cycle`, `on_unknown_prompt`, `get_autonomy`).
- `scripts/cmd_run.sh` — entry point for `dr-orchestrate run` + `--unknown-prompt` path.
- `scripts/tmux_manager.sh` — session / pane CRUD.
- `scripts/security.sh` — whitelist + escape + flock-safe cooldown + violation tracker.
- `scripts/secrets_backend.sh` — YAML backend with mode-0600 enforcement.
- `scripts/audit_sink.sh` — JSONL emit + schema v1 + schema v2 events + redaction.
- `scripts/semantic_parser.sh` — rule-based first-pass classifier.
- `scripts/rules_loader.sh` — 3-source rules merge (default → user → learned).
- `scripts/subagent_resolver.sh` — multi-backend AI CLI dispatch.
- `scripts/escalation_backend.sh` — mock | dev-bot escalation sink.
- `rules/default.yaml` — bootstrap slash-command patterns.
- `agents/dr-orchestrate-resolver.md` — declarative spec for the resolver subprocess.
- `commands/dr-orchestrate.md` — command surface.
- `tests/*.bats` — V-AC coverage (Phase 1 + Phase 2).

## Out of Scope (Phase 2)

Telegram bridge UI, auto-learned rules write path (Phase 3), real dev-bot HTTP
endpoint, Vault `secrets_backend.sh` rewrite, embedding/vector classification,
multi-host SSH, Docker / K8s orchestration, native Windows.
