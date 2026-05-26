# How-to · Opt-in `dr-output-stop` hook

**Source:** TUNE-0264.
**Status:** opt-in, not installed by `install.sh` / `update.sh` (intentional — see `tasks/TUNE-0264-task-description.md § Decisions D-3`).

The `dr-output-stop` Claude Code `Stop` hook adds programmatic enforcement on top of two markdown contracts that are otherwise advisory:

1. **Stage Header** (`skills/cta-format/SKILL.md § Stage Header`) — every task-scoped `/dr-*` response must begin with `**{TASK-ID} · {title}**`.
2. **Human Summary contract** (`skills/human-summary/SKILL.md § Output contract`) — `/dr-archive`, `/dr-compliance`, and `/dr-qa` responses must carry the canonical `## Отчёт оператору` / `## Operator summary` section with self-identifier preamble + four canonical sub-headings in order.

## What the hook does

| Trigger | First occurrence | Retry (`stop_hook_active=true`) |
|---------|------------------|----------------------------------|
| `/dr-*` response (not in Exception List) without Stage Header | stdout JSON `{"decision":"block","reason":"Stage Header missing..."}` → model regenerates | stderr advisory, exit 0 (retry budget = 1) |
| `/dr-archive` / `/dr-compliance` / `/dr-qa` response missing Operator summary section | `block` with `missing_section` | stderr advisory |
| Operator summary present but malformed (missing preamble, missing or extra sub-heading, wrong order) | `block` with finding-codes | stderr advisory |

Exception List (skipped by validator #1): `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` before Step 4 (no TASK-ID in the response).

Trigger list for validator #2: `/dr-archive`, `/dr-compliance`, `/dr-qa`. Other `/dr-*` commands skip validator #2 silently.

The hook is **fail-soft**: any internal error (corrupt transcript, missing file, regex crash, path outside `~/.claude`) degrades to exit 0 (allow). It is not a security gate — the text contracts in `skills/cta-format/SKILL.md` and `skills/human-summary/SKILL.md` are the canonical surface.

## How to opt in

Add the following block to `~/.claude/settings.json` under the top-level `hooks` key. If the file already has a `hooks.Stop` array, append the entry; if not, create it. The `~/.claude/settings.json` file is gitignored and operator-local.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/dev-tools/hooks/dr-output-stop.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Restart any active Claude Code session for the hook to take effect.

## How to verify the hook works

After opt-in, run the smoke probe against the most recent session transcript:

```bash
bash ~/.claude/dev-tools/smoke-dr-output-hook.sh
```

Output format:

```
header_found:{y|n}; human_summary:{ok|<finding>|skipped} (transcript: <path>)
```

- `header_found:y` — Stage Header detected on first non-empty line.
- `header_found:n` — Stage Header missing (the hook would have blocked).
- `human_summary:ok` — last invocation triggered validator #2 (one of `/dr-archive`, `/dr-compliance`, `/dr-qa`) and the contract held.
- `human_summary:skipped` — last invocation was not in the trigger list (validator #2 inactive).
- `human_summary:<finding>` — `missing_section` / `missing_preamble` / `missing_subheading_<N>` / `fifth_subheading` / `wrong_order`.

## How to opt out (rollback)

Remove the entry you added under `hooks.Stop[]` from `~/.claude/settings.json`. The hook stops firing immediately on next session start. The hook script itself stays in the framework repo (under symlink at `~/.claude/dev-tools/hooks/dr-output-stop.sh`) but is inactive without the settings entry.

For a full clean removal: `git revert` the framework commit that introduced `dev-tools/hooks/dr-output-stop.*` in the Datarim repo.

## How the validators are implemented

- `dev-tools/hooks/dr-output-stop.sh` — bash wrapper, ≤30 LoC, forwards stdin JSON to the Python helper. Exits 0 on any error (fail-soft contract).
- `dev-tools/hooks/dr-output-stop.py` — Python 3 helper using only the standard library (`json`, `re`, `pathlib`, `argparse`). Reads the JSONL transcript referenced by `transcript_path`, finds the last user/assistant pair, runs both validators sequentially.
- `tests/dr-output-stop.bats` — 18 integration cases covering valid/missing/exception/retry-advisory/corrupt/path-traversal for both validators.
- `tests/fixtures/dr-output/` — 13 JSONL transcript fixtures.

## Limitations

- The hook reads the transcript JSONL written by Claude Code. If CC switches transcript schema, the parser may need an update. Current support: `{type:"user"|"assistant", message:{content: str | [{type:"text",text:str}]}}` shapes.
- `transcript_path` is validated to live under `$HOME/.claude/` (literal path, no symlink resolution). Paths containing `..` segments or pointing outside `~/.claude/` are silently refused.
- Retry budget is one per validator per session-stop chain — if the model fails to comply on retry, the hook degrades to advisory rather than locking the operator into an infinite block loop.
- The hook is not a substitute for the markdown contracts. If `skills/cta-format/SKILL.md` or `skills/human-summary/SKILL.md` is removed, the hook still fires but its `reason` references will become stale.
