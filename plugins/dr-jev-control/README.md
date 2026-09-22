# dr-jev-control

Datarim control-plane integration for **Claude Code + TypeSafe Jev**.

It uses Jev for cheap bounded judgments and keeps Claude for execution/reasoning. The plugin includes:

- `dr-claude-jev` launcher: routes the initial task and starts the chosen agent CLI on the selected tier.
- **Two runtimes**: Claude Code (default) and Codex, via `--runtime {claude,codex}` — see below.
- `dr-claude-jev --live`: **dynamic routing** — a supervisor process re-evaluates the task at phase
  boundaries and switches model/effort mid-task (see below).
- **Kill switch**: `dr-jev off` disables the whole integration; Datarim, Claude Code and Codex run
  exactly as they did before it was installed, and the deterministic safety floor stays active.
- Jev Decision Summary printed before Claude starts, with `--explain` / `--quiet`.
- `UserPromptSubmit` routing: recommends Datarim skills, agent, command, template, model tier, validation, parallelism, and risk posture for each interactive turn.
- `PreToolUse` risk advisory: Jev evaluates potentially mutating tool calls. A deterministic local safety floor remains authoritative.
- Multi-skill selection with confidence thresholds: several skills can apply at once, and a
  low-confidence pick is reported but not imposed on Claude.
- Local catalog shortlisting: Jev sees only a small lexical shortlist rather than all 79+ skills on every call.
- JSONL decision ledger with secret redaction, readable via `dr-jev last` / `dr-jev stats`.
- Fail-open API behavior by default: a TypeSafe outage does not break ordinary Claude Code usage; deterministic Datarim safety rules still apply.

See `documentation/how-to/claude-code-jev-control-plane.md` in the Datarim root for installation and operating instructions.

## Operating modes

`balanced` is the default even when `--mode` is omitted.

```bash
dr-claude-jev "task"                    # balanced
dr-claude-jev --mode economy "task"
dr-claude-jev --mode balanced "task"
dr-claude-jev --mode quality "task"
```

Use `dr-jev help`, `dr-jev modes`, or `dr-claude-jev --help` to see commands and parameters.

## Inspecting decisions

```bash
dr-jev route --summary "task"    # compact operator-facing summary
dr-jev route --explain "task"    # summary + full probability JSON
dr-jev last                      # last decision, with probability bars
dr-jev stats                     # accumulated stats + predicted-vs-actual divergence
dr-claude-jev --quiet "task"     # suppress the summary
```

`dr-jev stats` is the feedback loop: it reports how decisive Jev is per axis and how often the
work turned out broader than the single component that was predicted. That divergence is the
input for the next architecture revision.

## Dynamic (live) routing

Static routing picks a model once, before the task starts. But the character of a task changes
while it runs — investigation, implementation, testing and documentation do not all need the same
capability. `--live` addresses that:

```bash
dr-claude-jev --live "task"
dr-claude-jev --live --mode quality "task"

# multi-turn supervision: keep driving until the agent emits the marker
python3 scripts/live_supervisor.py \
  --continue-prompt "Continue with the next step. Reply TASK_COMPLETE when finished." \
  --max-turns 8 "task"
```

### Runtimes

| | Claude Code | Codex |
|---|---|---|
| Tier change takes effect | in the **live session** (`control_request` on stdin) | on the **next turn** (`codex exec resume` with new settings) |
| What the tier maps to | model (`haiku`/`sonnet`/`opus`) + thinking budget | `model_reasoning_effort` (`low`/`medium`/`high`), plus a model when configured |
| Context across a change | preserved (session continues) | preserved (`resume` restores the thread) |
| Per-turn token usage | per assistant message | once, in `turn.completed` |

Codex has no live control channel, so its lever is resume-chaining: each turn is its own
`codex exec` process and may carry a different tier. Verified on codex-cli 0.153.4 that a fact
stored before an effort change is recalled after it, so context genuinely survives.

Codex model availability is account-dependent — on a ChatGPT-auth account only the configured
default was accepted and other ids returned HTTP 400. The default tier map therefore moves
**effort** and sends no `-m`. Assign real models per tier when you have them:

```bash
export DATARIM_CODEX_MODEL_HAIKU=...
export DATARIM_CODEX_MODEL_SONNET=...
export DATARIM_CODEX_MODEL_OPUS=...
export DATARIM_JEV_RUNTIME=codex     # make Codex the default runtime
```

### Running without the integration

Every path is fail-open: no API key, an unreachable API, a corrupt config or a missing config all
leave the host CLI working with no Jev input. Verified per hook, as a subprocess, for each mode.

The deterministic destructive-command floor is evaluated **before** any config is read, so
disabling Jev tunes off the *advisory* layer only — `rm -rf /`, `git push --force`,
`git reset --hard` and `DROP DATABASE` stay blocked.

```bash
dr-jev off                    # machine-wide, survives new shells
export DATARIM_JEV_DISABLE=1  # this shell only
dr-jev status                 # report which, if either, is in effect
dr-jev on                     # re-enable
```

### How it works, and why it is a process rather than a hook

No hook output field can change the session model. Verified on Claude Code 2.1.278: the
`PreModelSwitch` hook is *reactive* (it may allow/deny a switch that was already requested) and
every other hook event returns only `additionalContext` / `permissionDecision`. The channel that
actually *initiates* a switch is a `control_request` on stdin, available when Claude runs with
`--input-format stream-json --output-format stream-json`. So the supervisor owns that pipe:

```
task ──> Jev (initial route) ──> claude --model <tier>  (stream-json)
                                        │
                                   turn / phase boundary
                                        │
                                   Jev (re-route)
                                        │
                                   SwitchGate
                                        │
                        control_request set_model / set_max_thinking_tokens
```

### Why switching is gated

A model switch invalidates the prompt cache. Measured on 2.1.278: the turn before a switch read
30,775 tokens from cache; the first turn after it read 0 and re-created 27,614. Every switch
re-pays the whole conversation as cache-creation tokens, so a naive "ask Jev after every step"
loop spends more than it saves. `config/jev-control.json` → `live` therefore gates switching on:

| Guard | Default | Purpose |
|---|---|---|
| `escalate_threshold` | 0.75 | confidence needed to move up a tier |
| `deescalate_threshold` | 0.85 | higher bar to move down — downgrading mid-problem is the costlier mistake |
| `min_tokens_between_switches` | 25000 | do not re-pay the cache for essentially the same context |
| `min_seconds_between_switches` | 90 | suppress thrashing |
| `max_switches_per_session` | 6 | hard ceiling on re-cache spend |
| `turns_between_reroutes` | 2 | how often a Jev call is spent when the phase has not changed |
| `model_ceiling` / `model_floor` | per mode | a live switch can never leave the mode's envelope |

A phase change always earns a re-route; otherwise re-routes are paced by turn count. Escalation is
deliberately easier than de-escalation: a stuck agent burning turns on a cheap model is a worse
outcome than briefly overpaying.

Every blocked switch is recorded with its `blocked_by` reason — a switch that did *not* happen is
data about the policy, not a non-event.

Fail-open throughout: any Jev or transport failure leaves the session running on its current tier.
