# Datarim + Jev + Claude Code — Final Integration Report

> **Historical: Datarim 2.x only. Do not follow these steps.** The `dr-jev` and `dr-claude-jev`
> launchers, `install.py --scope user`, and an exported `TYPESAFE_API_KEY` describe the retired
> user-scope integration. Datarim 3.x installs Jev per project or per host and reads the key from a
> private file: see [INSTALL.md](INSTALL.md) and the [Jev CLI reference](documentation/reference/jev-cli.md).

This build integrates TypeSafe Jev as a System-One decision control plane in front of Claude Code and Datarim.

## Finalized behavior

- `balanced` is the default operating mode when no mode is specified.
- `economy`, `balanced`, and `quality` profiles are supported.
- Jev routes the initial Claude model and advises Datarim skill, agent, command, template, reasoning, risk, validation, and parallelism choices.
- Mode policy is deterministic around Jev: economy caps automatic routing at Sonnet; quality floors automatic routing at Sonnet; explicit `--model` always remains an operator override.
- The prompt hook propagates mode, agent fan-out budget, context budget, and validation policy to Claude/Datarim.
- Live API diagnostics use `dr-jev doctor --api`.
- CLI discovery is built in: `dr-jev help`, `dr-jev modes`, `dr-claude-jev --help`.
- macOS symlink resolution and `DATARIM_JEV_HOME` are supported.
- Jev API transport has curl-first networking, retry/backoff, timeout diagnostics, and Python fallback.
- Routing decisions are recorded in the JSONL ledger without prompt text by default.
- Hooks call the Jev API under a reduced `hook_timeout_seconds`/`hook_retries` budget (default 4s / 0 retries), separate from the interactive-CLI budget (`timeout_seconds`/`retries`) used by `dr-jev route`/`doctor --api`. The registered hook `timeout` in installed Claude settings covers this reduced budget's worst case, so a Jev outage fails open quickly instead of the hook being killed mid-retry.
- `hook_pre_tool.py` and `route.py`'s CLI fallback path no longer assume a fully-populated config: a missing `routing.risk_thresholds` or an unreadable/invalid config file both resolve to the documented fail-open behavior instead of an unhandled traceback.

## Start here

Read `JEV-QUICKSTART.md`, then run:

```bash
python3 plugins/dr-jev-control/scripts/install.py --scope user
dr-jev doctor --api
dr-claude-jev "your task"
```
