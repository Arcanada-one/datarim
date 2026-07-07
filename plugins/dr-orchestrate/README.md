# dr-orchestrate Plugin — Phase 2 (Subagent Inference + Bot-Interaction Interface)

> Class B plugin. Status: Phase 2 (Datarim v2.5.0, plugin v0.3.0).

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

The orchestrator's effective autonomy is **resolved per-space at runtime** via the following chain:

1. `space.yml § autonomy.policy` — the active space's machine-readable policy (e.g. `spaces/arcanada/space.yml`).
2. `dev-tools/resolve-space-autonomy.sh gate --action <kind>` — evaluates the policy, returns `auto` or `escalate`.
3. `scripts/action_gate.sh gate --action <kind>` — thin wrapper that delegates to the resolver above.

**In a full-autonomy (root-managing) space such as Arcanada, the orchestrator and its agents execute ALL reversible work autonomously and escalate ONLY hard-gated floor actions.** Do not ask the operator about reversible actions (rsync, git operations on feature branches, writing PRDs, conveying briefs, cloning repositories, or resetting a local clone). The hard-gated floor (`rules/fb-rules.yaml § hard_gated_actions`) — financial/legal operations, irreversible database mutations, git history rewrites, public publications without confirmation — always escalates regardless of per-space policy.

Pipeline phases by feature set (not a fixed autonomy level):

- **Phase 1** — lean rule-based tmux runner.
- **Phase 2** — multi-backend subagent inference (coworker → claude → codex) + race-safe cooldown + audit schema v2.
- Phase 3 (planned) — auto-learning rules, Y/N callback, 24 h re-validation.

## Subagent Inference (Phase 2)

When the rule-based parser returns `confidence: 0` (parser miss), `cmd_run.sh`
dispatches to `subagent_resolver.sh`, which classifies the pane text via a
configurable fallback chain of AI CLI backends:

| Backend | Invocation | Notes |
|---------|-----------|-------|
| `coworker-deepseek` (default primary) | `coworker ask --provider deepseek --profile classifier` | OSS coworker CLI; vendor-neutral classifier, not artifact review |
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

Resolver JSON may also include `action_kind` and `action_payload`.
`cmd_run.sh` sends these through `scripts/action_gate.sh` before execution.
The gate reads explicit per-space `autonomy.policy`, writes its audit record
first, and fails closed on missing, malformed, unknown, or unresolved policy.

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

## Bot-Interaction Interface (v0.3.0+)

Programmatic IO surface alongside the tmux pane. Lets a bot (or any HTTP client)
submit prompts to the orchestrator and receive escalation / progress events.

**Wire contract:** `openapi/orchestrator-interface.yaml` (OpenAPI 3.1).

- **Inbound** — `POST /orchestrator/input` (Bearer auth, JSON body
  `{session_id, command, ts, meta?}`). Default response `202 Accepted`. Sync
  shortcut (`200` + inline body) only for whitelist commands (`dr-status`,
  `dr-help`) when the client sends `X-Sync-Timeout` (hard-cap ≤ 2000 ms).
- **Reference impl** — `adnanh/webhook` v2.8.3 (Go single binary, MIT) +
  `config/hooks.yaml` + `scripts/orchestrator-input-handler.sh`. Loopback bind
  `127.0.0.1:8090` (Tier 1, single-tenant). Bearer secret via Vault ref
  `vault:secret/datarim/orchestrator/bearer`.
- **Inbox FIFO** — handler atomically writes ULID-named JSON files into
  `~/.local/share/datarim-orchestrate/inbox/`. `cmd_run.sh` drains the inbox
  oldest-first per cycle and injects `.command` as `UNKNOWN_TEXT` into the
  existing semantic-parser → resolver pipeline.
- **Outbound** — `_emit_devbot` in `escalation_backend.sh`. Backends switched
  via `DR_ORCH_OUTBOUND_BACKEND`:
  - `callback` (default) — HMAC-SHA256 sign + `X-Timestamp` (300 s replay
    window) + curl POST to `DR_ORCH_ESCALATION_DEVBOT_URL`. HMAC secret via
    Vault ref `vault:secret/datarim/orchestrator/hmac_secret`.
  - `redis` (opt-in) — `redis-cli PUBLISH orchestrator-out:{session_id}` via
    `DR_ORCH_OUTBOUND_REDIS_URL`.
- **Activation gate** — when `DR_ORCH_ESCALATION_DEVBOT_URL` is unset,
  `_emit_devbot` silently `return 0` (noop). Rollback = `unset` the env var.
- **Contract tests** — `tests/contract/run-schemathesis.sh` + CI workflow
  `.github/workflows/dr-orchestrate-contract.yml` start the reference impl on
  an ephemeral port and run schemathesis property-based fuzz against the spec.
- **Pre-activation gate** — `dev-tools/check-agent0017-live.sh` (curl `/healthz`
  + smoke `POST /prompts`) MUST pass before operators set the production env.

## Backend Install

`coworker` and `claude` should be on `$PATH` of the host that runs the plugin.

```bash
# coworker (OSS)
curl -fsSL https://raw.githubusercontent.com/Arcanada-one/coworker/main/install.sh | bash

# claude CLI — see https://docs.claude.com/en/documentation/claude-code
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
- `scripts/escalation_backend.sh` — mock | dev-bot escalation sink (callback HMAC + Redis pub/sub backends).
- `scripts/orchestrator-input-handler.sh` — inbound HTTP body validator + atomic inbox enqueue.
- `scripts/outbound-hmac-sign.sh` — HMAC-SHA256 sign + curl POST for callback backend.
- `scripts/outbound-redis-publish.sh` — redis-cli PUBLISH wrapper for Redis backend.
- `openapi/orchestrator-interface.yaml` — OpenAPI 3.1 wire contract.
- `config/hooks.yaml` — adnanh/webhook trigger config.
- `rules/default.yaml` — bootstrap slash-command patterns.
- `agents/dr-orchestrate-resolver.md` — declarative spec for the resolver subprocess.
- `commands/dr-orchestrate.md` — command surface.
- `tests/*.bats` — V-AC coverage (Phase 1 + Phase 2).

## Bot Interaction Config

`user-config.template.yaml` contains a `bot_interaction:` block that controls
how the orchestrator's IO is routed at startup.

**Provider switching:**

| `provider` value | Behaviour |
|-----------------|-----------|
| `terminal` (default) | No env mutations — existing tmux-pane behaviour preserved. |
| `agent0017` | Exports `DR_ORCH_ESCALATION_BACKEND=dev-bot`; sets `DR_ORCH_ESCALATION_DEVBOT_URL` when `endpoint` is non-empty; activates Redis outbound when `outbound_backend: redis`. |

Copy `user-config.template.yaml` → `user-config.yaml`, set `chmod 600`, fill in
the relevant fields, and restart the orchestrator. Reverting to terminal mode is
as simple as setting `provider: terminal` (or removing the block entirely).

See `openapi/orchestrator-interface.yaml` for the full wire contract and
`scripts/bot_interaction_dispatcher.sh` for the sourced env-export logic.

## Out of Scope (Phase 2 + v0.3.0)

Telegram bridge UI, auto-learned rules write path (Phase 3), Vault
`secrets_backend.sh` rewrite, embedding/vector classification, multi-host SSH,
Docker / K8s orchestration, native Windows, stateful session store (Redis
SETEX deferred), SSE/WebSocket outbound transport (deferred).
