# Handoff: the two DEV-AI test sessions

Written 2026-09-23. Every command below was executed or dry-run on the host
before being written down; the session ids come from the live processes, not
from memory.

## What is running

Both sessions live in `tmux` on `aether` (ssh alias for DEV-AI), both working in
`/home/aether/code/aether/local-env`, both reporting their task complete.

| tmux session | Client | Session id | State |
|---|---|---|---|
| `jev-DEV-1962` | Claude Code | `ee2123ae-f89a-4ae9-9811-62ce847c08b0` | done 9:31 PM, 40% context used |
| `jev-DEV-1926` | Codex (`gpt-6-astra`, effort high) | `01a095ef-1c17-7183-8482-65d8d5cd69f9` | "Goal achieved", worked 3h 14m |

A third session, `jev-autopilot`, runs `/tmp/autopilot3.sh`: a loop that answers
approval dialogs in those two sessions automatically. **It is still armed.** It
will press "Yes, proceed" on any new confirmation prompt that appears there.
Kill it before you resume work you want to approve yourself:

```bash
ssh aether 'tmux kill-session -t jev-autopilot'
```

## Taking them over

Attach to watch what is there, without changing anything:

```bash
ssh aether
tmux attach -t jev-DEV-1962      # detach again with Ctrl-b d
tmux attach -t jev-DEV-1926
```

To continue a task **through Jev**, so routing and the hooks apply, start from
the project and activate the runtime first:

```bash
ssh aether
cd ~/code/aether/local-env
source .datarim-runtime/activate.sh
```

Then resume the client you want:

```bash
# Claude Code — DEV-1962
jevclaude --resume ee2123ae-f89a-4ae9-9811-62ce847c08b0 "what is left on DEV-1962?"

# Codex — DEV-1926. resume does NOT inherit model or effort; state them.
jevcodex --resume 01a095ef-1c17-7183-8482-65d8d5cd69f9 --effort high \
    "what is left on DEV-1926 and DEV-1679?"
```

Verified by `--dry-run` before writing: both resolve to the right binary, the
right project, `scope: host`, `datarim_enabled: true`, `network_calls: 0`.

Add `--dry-run` yourself to see what would run without running it.

## Checking it is really working

```bash
jev doctor            # findings: [] and codex_hook_trust.state: trusted
jev stats             # routing decisions recorded for this project
```

If `doctor` reports `modified`, Codex has stopped running those hooks because
their command changed since you trusted them: open `codex` in the TUI and choose
**Trust all and continue**. Hosts installed with the stable `jev-hook` command
keep their approval across upgrades — see the control-plane how-to.

## Caveats measured, not assumed

- The Codex session's own status line shows `gpt-6-astra high`; `resume`
  without `--effort` would silently drop to the default.
- The agent process for Codex is **not** the tmux pane pid — that is a node
  wrapper. The real process is its child. This matters if you check liveness
  with `ps`/`/proc`.
- Ledger silence during context compaction is normal: no tools are called, so
  no hook events are produced. It is not a fault.
