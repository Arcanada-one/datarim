# Datarim CLI

## Overview

The `datarim` CLI is the external-agent surface for Datarim — it lets a non-interactive process (Codex, Cursor, or a custom agent) drive the full `/dr-*` pipeline through the existing `/dr-orchestrate v2.5.0` webhook. AAL 3 is opt-in only and requires an `accepted-risk-aal.yml` entry `tune-0268-aal3-cli`. Phase 3 ships HTTP dispatch plus six AAL 3 mitigations.

## When to use CLI vs slash command

| Aspect | CLI (`datarim run /dr-*`) | Slash command (inside Claude Code session) |
|--------|---------------------------|--------------------------------------------|
| Interactive Q&A | Pre-confirmed flows only | Full interactive Q&A supported |
| AAL | 3 (opt-in via `accepted-risk-aal.yml`) | 2 (default) |
| Audit log | `datarim/audit/cli-audit-YYYY-MM-DD.jsonl` (90d retention) | Session JSONL |
| Kill-switch | `~/.config/datarim-cli/HALT` sentinel | SIGINT |
| Token cost | None (HTTP webhook only) | Current session |

## Installation

```bash
cd code/datarim/cli && ./install.sh
```

The installer: (a) prints the bilingual AAL 3 warning, (b) validates that `accepted-risk-aal.yml` contains entry `tune-0268-aal3-cli` and that the entry is not expired (exits 23 otherwise), (c) symlinks `code/datarim/cli/datarim` to `/usr/local/bin/datarim` (or `$HOME/.local/bin/datarim` if no sudo).

- Uninstall: `./install.sh --uninstall`
- Dry-run: `./install.sh --dry-run`

## Backend listener requirement

`datarim run <slash-cmd>` is an HTTP client only — it dispatches requests to a separately-running webhook listener and does **NOT** ship that listener itself. By default the client targets `http://127.0.0.1:8090/hooks/orchestrator-input` (override via `DATARIM_CLI_WEBHOOK_URL`). Without a listener you will see:

```
[http] connect-failed-after-retries http://127.0.0.1:8090/hooks/orchestrator-input
Exit code: 21
```

This is documented behaviour, not a defect. The listener is the **reference implementation of the `dr-orchestrate` plugin** — open-source [`adnanh/webhook`](https://github.com/adnanh/webhook) v2.8.3 (Go single-binary, MIT-licensed). It maps incoming HTTP requests to shell commands declared in `plugins/dr-orchestrate/config/hooks.yaml`. **It is not part of the Datarim framework runtime** — it is a single small external binary that you start manually when you want to expose `/dr-*` to non-interactive agents (Codex CLI, Cursor, cron, custom HTTP clients).

To stand up the listener:

```bash
# 1. Activate the plugin (creates ~/.claude/plugins/dr-orchestrate symlinks).
/dr-plugin enable dr-orchestrate

# 2. Install adnanh/webhook (one option — see https://github.com/adnanh/webhook for others).
brew install webhook                  # macOS
# go install github.com/adnanh/webhook@v2.8.3   # any platform with Go

# 3. Start the listener (foreground; use launchd/systemd/tmux for daemonisation).
webhook -hooks plugins/dr-orchestrate/config/hooks.yaml -port 8090 -verbose
```

Security boundary: the bind `127.0.0.1:8090` is **loopback-only (Tier 1 single-tenant)**. The listener does not expose any external network interface; only processes on the same machine can reach it. Auth is Bearer token (Vault ref `vault:secret/datarim/orchestrator/bearer`); outbound emissions are HMAC-SHA256 signed with a 300-second replay window (Vault ref `vault:secret/datarim/orchestrator/hmac_secret`). Activation is gated — when `DR_ORCH_ESCALATION_DEVBOT_URL` is unset, outbound `_emit_devbot` is a no-op.

If you only ever drive `/dr-*` from a Claude Code session, you do not need the listener. The CLI is the alternative path, not the default.

## Agent identity

The `$DATARIM_CLI_AGENT_ID` environment variable is mandatory and must be a UUID v7. A missing or malformed value exits 22. Generate a compliant ID with `code/datarim/cli/lib/uuid7-gen.sh`. UUID v7 is time-sortable and considered GDPR-low-risk.

## Subcommands

### `datarim run <slash-command> [args]`

Dispatches the slash command to `/dr-orchestrate` via HTTP. Sync whitelist (X-Sync-Timeout 1500ms, total ≤2000ms): `/dr-status`, `/dr-help`. All other commands route asynchronously — HTTP 202 with a `job_id`; follow-up via Redis Sub or HTTP GET poll. Non-idempotent commands (`/dr-do`, `/dr-archive`, `/dr-prd`, `/dr-plan`, `/dr-design`, `/dr-qa`, `/dr-compliance`, `/dr-verify`) refuse the sync path and exit 26.

### `datarim audit log [--day YYYY-MM-DD]`

Prints today's audit JSONL, or a specified day if the `--day` flag is provided.

### `datarim audit halt | resume`

Engages or disengages the kill-switch sentinel file.

### `datarim audit purge`

Applies 90-day retention: files untouched for <90d remain as-is, files 90-180d old are gzipped to `datarim/audit/archive/`, files >180d old are deleted.

### `datarim audit stats`

Prints summary counters for the audit log.

### `datarim version | help`

Self-explanatory.

## AAL 3 mitigations (Phase 3 ships all six)

- **Dual-channel notifier** — every irreversible action emits a Telegram alert via `@ArcanadaAssistantBot` before the action proceeds; zero ACK within 3000ms causes exit 18 and the action is aborted.
- **JSONL audit log** — schema version 1, 10 keys, flock atomic append (portable python3 fcntl wrapper on macOS).
- **Kill-switch sentinel** — presence of `~/.config/datarim-cli/HALT` triggers exit 17 on every subcommand.
- **`accepted-risk-aal.yml` entry** — invocation-time gate (1h cache); missing or expired entry exits 23.
- **Bilingual install warning** — 6 RU + 6 EN canonical lines printed on every install run.
- **UUID v7 agent identity** — env-only enforcement (no `--as` flag in Phase 3).

## Exit code reference

| Exit code | Description |
|-----------|-------------|
| 0 | Success |
| 17 | Kill-switch sentinel present (`HALT` file) |
| 18 | Dual-channel notifier timed out (no ACK in 3000ms) |
| 21 | Invalid or missing slash command |
| 22 | Missing or malformed `$DATARIM_CLI_AGENT_ID` (must be UUID v7) |
| 23 | `accepted-risk-aal.yml` entry `tune-0268-aal3-cli` missing or expired |
| 24 | HTTP dispatch failure / network error |
| 25 | Command returned non-zero from webhook |
| 26 | Non-idempotent command requested on sync path |
| 27 | JSONL audit write failure |

## File paths

- `cli/datarim` — entry point
- `cli/lib/` — http, audit, notify, kill-switch, agent-id, accepted-risk-check, uuid7-gen, slash-classification.yaml
- `cli/subcommands/run.sh`, `audit.sh`
- `cli/install.sh`, `cli/install-warning.sh`
- `accepted-risk-aal.yml` — repo root
- `dev-tools/check-cli-audit-schema.sh`
- `dev-tools/check-accepted-risk-aal.sh`
- `datarim/audit/cli-audit-YYYY-MM-DD.jsonl` — workspace only

## Related

- PRD: `prd/PRD-TUNE-0271.md` (Phase 3) + `prd/PRD-TUNE-0268.md` (epic)
- Plan: `plans/TUNE-0271-plan.md`