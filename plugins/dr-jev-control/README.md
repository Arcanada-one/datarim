# Jev control plane

Optional project-local routing for Datarim with Codex, Claude Code, and Cursor.
Jev recommends a capability tier and relevant catalog components; the selected
native agent performs the work. An API outage leaves the native client available.
Speed, quality, and cost improvements require measurement on real tasks.

## Install and use

Install with [INSTALL.md](../../INSTALL.md): `./install.sh --project /path/to/project
--with-jev` for this project only (no user-level hooks, skills, instructions, or
launchers), or host-wide Jev with `scripts/jev_host_install.py` plus
`--with-jev --host-jev` on the project.

- [Datarim with Jev tutorial](../../documentation/tutorials/initialize-datarim-with-jev.md)
- [Configuration and operation](../../documentation/how-to/configure-and-use-jev.md)
- [Four entrypoints and CLI flags](../../documentation/reference/jev-cli.md)

Activate the project's `.datarim-runtime/activate.sh`, then use `jevcodex`,
`jevclaude`, `jevcursor`, or `jev --agent=codex`. `jev doctor` checks local
prerequisites; `jev doctor --api` explicitly tests API connectivity. Native AGENTS
loading and session continuity need separate live checks.

## Routing and continuity

| Client | Tier mapping | Live supervisor boundary |
|---|---|---|
| Claude Code | Model tier and thinking budget | Control requests in the active stream |
| Codex | Reasoning effort; optional explicitly configured model | Resume the exact thread on the next turn |
| Cursor | Explicit model mapping; no common effort flag | Resume the exact session on the next turn |

The supervisor refuses missing or changed continuation IDs. A failed client turn
is not a completed turn. Cursor mappings must use models available to the account;
a missing mapping is reported instead of being recorded as an applied switch.

## Project hooks and state

`--with-jev` registers native hooks for all three clients in the project:
`.claude/settings.local.json`, `.codex/hooks.json` and `.cursor/hooks.json`. They
provide prompt routing, pre-tool risk advice, post-tool validation and the
deterministic safety floor, which refuses destructive shell commands without a
key or network. Codex runs them only after you trust them in its TUI.

`jev off` disables Jev advice for the current project. The deterministic safety
floor remains active while the registered project hooks are installed.
`DATARIM_JEV_DISABLE=1` disables advice for the invoking shell. Neither switch
turns another project on or off.

The ledger is under `.datarim-runtime/state/jev/`; use `jev stats` to inspect
predicted versus observed decisions. Key material lives outside that directory
in `config/credentials/jev/api-key`. The installer preserves both across updates.

## Switching policy

Switches are evaluated at phase boundaries and paced between phases. Defaults:

| Setting | Value |
|---|---|
| Escalation confidence | 0.75 |
| De-escalation confidence | 0.85 |
| Minimum tokens between switches | 25000 |
| Minimum seconds between switches | 90 |
| Maximum switches per session | 6 |
| Turns between periodic re-routing | 2 |

Mode-specific floors and ceilings are in the project `jev-config.json`. The
ledger records blocked switches and their reasons. Switching can incur cache
recreation costs; prior single-session measurements are not a universal saving
or performance guarantee.
