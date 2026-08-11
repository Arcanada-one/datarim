# Reference: Datarim MCP server

`cli/mcp/datarim-mcp-server.sh` is a [Model Context Protocol](https://modelcontextprotocol.io)
server that exposes Datarim commands, skills, and agents to any MCP client
(primarily **Codex CLI**) over **stdio JSON-RPC 2.0**. It lets Codex recognise
Datarim as a first-class MCP source and invoke commands through typed tool
calls, complementing the `~/.codex/AGENTS.override.md` filesystem catalogue
(which remains as graceful degradation).

## Transport

- **stdio**, newline-delimited JSON-RPC 2.0 (one message per line, no embedded
  newlines). stdout carries **only** protocol messages; all diagnostics go to
  stderr.
- No network listener; the server is spawned by the MCP client.
- Dependencies: `bash` 4+, `jq`, `awk`, `realpath`. No install step of its own.

## Configuration

`DATARIM_ROOT` (env) points at the framework install root (the directory
containing `commands/`, `skills/`, `agents/`, `VERSION`). It defaults to the
repo root resolved from the script location. `install.sh --with-codex`
registers the server automatically (see below).

| Env | Default | Meaning |
|-----|---------|---------|
| `DATARIM_ROOT` | repo root | framework tree to serve |
| `MCP_BODY_CAP` | `262144` | max bytes returned per artefact body |
| `MCP_MAX_LINE` | `65536` | max bytes accepted per JSON-RPC request line |

The server refuses to start if `DATARIM_ROOT` is missing the
`commands`/`skills`/`agents` sentinel, or resolves to `/`, `$HOME`, or a
`config/credentials` path.

## Capabilities

The server advertises **`tools`** only. (Codex's MCP client consumes tools;
`prompts/*` and `resources/*` handlers exist for other clients but are not
advertised.)

### Tools

| Tool | Input | Returns |
|------|-------|---------|
| `datarim_list_commands` | — | JSON array `[{name, description}]` of `/dr-*` commands |
| `datarim_run_command` | `{name, args?}` | the command's full instruction body (the caller executes it) |
| `datarim_list_skills` | — | JSON array of skills |
| `datarim_get_skill` | `{name}` | the skill body |
| `datarim_list_agents` | — | JSON array of agents |
| `datarim_get_agent` | `{name}` | the agent body |

`name` is the artefact's file/directory basename (e.g. `dr-status`,
`brainstorming`, `architect`), so a `list` result round-trips directly into a
`get`/`run`. The server reads and returns file text — it never executes
artefact content and makes no network calls.

## Error semantics

- Unknown JSON-RPC **method** → error `-32601`.
- Unknown **tool** name or missing/invalid required argument → error `-32602`.
- Valid tool with an unknown **target** (e.g. `datarim_run_command` for a
  non-existent command) → a tool result with `isError: true` (so the model can
  recover), never leaking a filesystem path.
- Malformed / non-JSON request line → `-32700`; the read loop continues.
- Batch (array) request → `-32600` (batching was removed in MCP 2025-06-18).
- Notifications (no `id`, e.g. `notifications/initialized`) get no response.

## Security

`name` arguments are untrusted (model-supplied). Defence layers:
allowlist charset `^[a-z0-9][a-z0-9._-]{0,63}$` (no `..`) → membership in the
live directory listing (symlinks excluded) → realpath-confinement under the
exact subdir (`commands/`|`skills/`|`agents/`) → regular-file check. Client
data reaches `jq` only via `--arg`/`--argjson` (fixed filters, no program
building, no `eval`). Input/output are byte-capped.

## Installation

```text
./install.sh --with-codex              # registers [mcp_servers.datarim]
./install.sh --with-codex --no-codex-mcp   # opt out of MCP registration
```

Registration edits `~/.codex/config.toml` directly (idempotent, byte-identical
on re-run) — see the how-to guide `documentation/how-to/multi-runtime.md`.

## Manual smoke test

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  | DATARIM_ROOT=$PWD cli/mcp/datarim-mcp-server.sh
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  | DATARIM_ROOT=$PWD cli/mcp/datarim-mcp-server.sh | jq '.result.tools[].name'
```

Verify a live client with `codex mcp get datarim` (recognition) and a `codex`
session (`tools/list` enumerates the six `datarim_*` tools).
