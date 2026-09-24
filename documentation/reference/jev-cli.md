# Jev CLI reference

After project-local activation:

```text
jevcodex [options] [task] [-- client-arguments...]
jevclaude [options] [task] [-- client-arguments...]
jevcursor [options] [task] [-- client-arguments...]
jev --agent={codex,claude,cursor} [options] [task] [-- client-arguments...]
jev doctor [--agent=...] [--api]
jev stats
jev on
jev off
jev permissions [full|ask]
jev trust
```

Installing the launchers: [INSTALL.md](../../INSTALL.md).

The braces denote alternatives; pass one agent. An alias cannot select a
different agent. An omitted task starts the client's interactive session without
an initial routing request.

| Option | Meaning |
|---|---|
| `--agent` | Required on `jev` for client launch; fixed by each alias |
| `--mode` | `economy`, `balanced`, `quality`; default balanced |
| `--model` | Explicit supported client model, direct mode |
| `--effort` | low/medium/high; Claude/Codex direct mode only |
| `--resume ID` | Resume exact client session, direct mode |
| `--print` | Non-interactive client invocation |
| `--live` | Phase-boundary supervised execution |
| `--max-turns N` | Positive live turn cap |
| `--max-seconds N` | Positive live wall-clock cap |
| `--continue-prompt TEXT` | Live follow-up after a completed turn |
| `--done-marker TEXT` | Live task completion marker |
| `--no-route` | Disable Jev for this invocation |
| `--dry-run` | Resolve local scope/client without reading key or contacting Jev |
| `--api` | Explicit network verification with doctor |
| `--help`, `--version` | Inspect interface without project activation |
| `--` | Separate client flags from dispatcher flags |

Client flags that relocate the workspace are rejected. Launch from the approved
context instead. Permission-bypass flags are added only after `jev permissions
full` (or with `JEV_PERMISSIONS=full` for one launch), and never when you pass
your own permission option: `--dangerously-skip-permissions` for Claude Code,
`--dangerously-bypass-approvals-and-sandbox` for Codex, `--force --approve-mcps`
for Cursor. `jev permissions ask` removes them; `jev permissions` shows the
stored choice. The choice is stored per project, or per host for host Jev.

`jev trust` re-grants Codex trust to Jev's own host hooks after another tool
moved them in `~/.codex/hooks.json`; hooks you disabled stay disabled. With host
Jev, `jevcodex` does the same before each launch unless `JEV_NO_AUTO_TRUST=1`.
Neither touches project-level hooks.
Direct mode replaces the dispatcher process, preserving terminal streams and the
client's exit status. Dispatcher errors use 2; a missing executable uses 127;
doctor findings use 1. Live exits follow the supervisor's recorded stop reason.

Scope is checked before reading credentials. The dispatcher sets local runtime,
config, state and key-file paths; stale global Datarim path variables do not
select another installation. `CLAUDE_BIN`, `CODEX_BIN`, and `CURSOR_BIN` select
executables for an explicitly configured client. Model mapping variables are
documented in [configuration](../how-to/configure-and-use-jev.md).

Legacy `dr-jev` and `dr-claude-jev` are not installed globally. Use the entrypoints
above. Capabilities must be verified on each installed client version; the
presence of a runtime implementation is not evidence of a successful real API session.
