# Jev control plane

Optional project-local routing for Datarim with Codex, Claude Code, and Cursor.
Jev recommends a capability tier and relevant catalog components; the selected
native agent performs the work. An API outage leaves the native client available.
Speed, quality, and cost improvements require measurement on real tasks.

## Install and use

Install with [INSTALL.md](../../INSTALL.md): `./install.sh --project /path/to/project`
prints the questions to ask and the flags for each answer. The Jev answer
"project" installs Jev for this project only (no user-level hooks, skills,
instructions, or launchers); "host" uses host-wide Jev from
`scripts/jev_host_install.py`.

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

`--with-jev` registers native hooks in the project for the clients selected with
`--client` (all three by default):
`.claude/settings.local.json`, `.codex/hooks.json` and `.cursor/hooks.json`. They
provide prompt routing, pre-tool risk advice, post-tool validation and the
deterministic safety floor, which refuses destructive shell commands without a
key or network. Codex runs them only after you trust them in its TUI.

`jev off` disables Jev advice for the current project. The deterministic safety
floor remains active while the registered project hooks are installed.
`DATARIM_JEV_DISABLE=1` disables advice for the invoking shell. Neither switch
turns another project on or off.

The pre-tool cost guard sends sudoers/systemd paths and installation, bootstrap,
setup, provision or deploy signals to the native `risky` question even without
`sudo`: the executor may already be privileged. Explicit working directories,
Write/Edit paths and patch headers (including rename destinations) are inspected.
Protected path signals include `/etc`, `/usr/local` and `/var/lib`. Unknown
repository script invocations (including scripts named as tests), operational
deploy/release/sync/migrate targets, credential login and dynamic agent runs are
evaluated because their bodies may hide DB, API or privileged writes. Script
contents and the hook process uid are not used to infer safety. Oversized commands
are treated as unknown to bound argv parsing work.
Files are never opened by this guard; edit bodies and inline program/here-doc
bodies are omitted. Commands with recognized credential options (for example
`--api-key VALUE`) and oversized fields are omitted whole. Shell descriptors
still include ordinary command arguments, with credential scrubbing applied
before bounding the JSON. Fixed privileged-path categories and risk signals remain
when command source is omitted; credential options suppress command-derived paths
entirely. No raw substrings are recovered from omitted source text.
These are conservative signals, not proof of a write or a complete shell parser.
Opaque shell `-c` code and substitutions are evaluated conservatively. Quoted
or escaped `>` and terminal `<placeholder>` descriptors do not by themselves
count as output-file redirections. Exact `/dev/null` targets and fd duplication
are excluded only from the redirection signal; neighboring writes and independent
risk signals still evaluate. Quoted comparisons such as `print(1 >= 0)` stay cheap.
A following target, such as `<data> out`, is a real output redirection.
Risk names are checked in executed argv after quote/ANSI-C normalization and
wrapper removal, with additive legacy command-word coverage: normalization must
not erase an installed guard signal. Privilege wrappers remain signals themselves.
This retains some questions about quoted command words, literal arrows and
control-flow redirects; it is conservative coverage, not a claimed cost saving.
Opaque flock/xargs/busybox calls, package installations and interpreter stdin
execution are evaluated; pipeline bodies are omitted from model descriptors.
An unresolved command variable requires advice. Read-only
argument substitutions and standard Python test-runner operands stay cheap.
Advice remains optional and fail-open on an API error. A high score requests
native permission only with `enforce_jev_denials`; this guard does not itself
authorize commands or establish that an arbitrary script is safe.

The operational no-regression test replays the hash-pinned 783-command review
corpus through the real hook for both clients and asserts that every installed
question remains evaluated or locally denied. The private inputs are not shipped
in this public repository. Delivery validation must set
`JEV_GUARD_REPLAY_CORPUS` to the approved file and
`JEV_GUARD_REPLAY_REQUIRED=1`; missing or altered input fails this gate. Without
the input, public CI explicitly skips that test and cannot establish operational
baseline coverage. The replay mocks evaluation and never executes command strings.

The ledger is under `.datarim-runtime/state/jev/`; use `jev stats` to inspect
predicted versus observed decisions. Key material lives outside that directory
in `config/credentials/jev/api-key`. The installer preserves both across updates.

`config/jev-control.json` in this plugin is the **template**, not a live settings
file: a project install copies it to `.datarim-runtime/jev-config.json`, host
Jev to `~/.config/jev/config.json`. Edit the copy. `jev doctor` names the file
it reads as `config_path`.

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
