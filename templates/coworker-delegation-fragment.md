# Coworker Delegation — runtime mandate fragment

> **Source of truth.** This fragment is generated/copied into every agent
> runtime that supports `coworker`:
> - Claude Code → `~/.claude/CLAUDE.md` § Coworker Delegation.
> - Codex CLI → `~/.codex/AGENTS.override.md` prepend emitted by
>   `install.sh generate_codex_agents_manifest`.
> - Cursor IDE → `~/.cursor/rules/coworker-delegation.mdc` mirrored from
>   `templates/coworker-delegation.mdc` by `install.sh --with-cursor`.
>
> Edit this file → re-run `install.sh --with-claude --with-codex --with-cursor`
> (or equivalent fanout) → consumers regenerate. Do NOT hand-edit downstream
> copies.

## Rule of thumb

**Claude / Codex = thinking. Coworker = I/O.**

`coworker` is a CLI tool (`~/.local/bin/coworker`) that offloads bulk I/O to
a configurable external LLM (Moonshot / Groq / OpenRouter / DeepSeek /
OpenAI) via the OpenAI-compatible API. Provider/model switchable per call.

## MANDATORY delegation (no exceptions, do not rationalize)

### Never write directly — always `coworker write --profile datarim` first, then edit

- First draft of PRD, plan, design docs, task-description.
- Articles in `wiki/`, posts in `Social Media/`, ecosystem-site docs.

### Exempt (operator decision, 2026-05-24)

- `archive-{TASK-ID}.md` and `reflection-{TASK-ID}.md` — generated at the
  end of the pipeline (`/dr-archive`), when the agent already holds full
  context from the current cycle. Coworker does not save tokens here (spec
<!-- gate:history-allowed -->
  ≈ final text) and has repeatedly fabricated (CONN-0213 / AUTH-0084
<!-- /gate:history-allowed -->
  precedent). Direct `Write` allowed. If context is empty (recovering a
  stale archive months later) the operator picks coworker manually.

### Always `coworker ask` if ANY trigger fires

- Total lines to read **>600** (sum across files, not per file).
- **≥3 files** for one question.
- Any read from `wiki/_raw_/`.
- `/dr-do`, `/dr-prd`, `/dr-plan`, `/dr-archive`, `/dr-dream`, `/dr-qa`
  bootstrap (`tasks.md` + `backlog.md` + `CLAUDE.md` + PRD + plan) — ONE
  call, not per-file `Read`.
- `git diff` / `git log -p` output >~200 lines.

## Tools

```text
coworker ask    --provider <p> --profile <pr> --paths <f1> <f2> ... --question "<q>"
coworker write  --provider <p> --profile <pr> --spec "<what>" --context <ref1> ... --target <out>
coworker stats  --since 7d --by profile
coworker debug  --hash <sha256-prefix>           # raises blob if COWORKER_LOG_CORPUS=1
extract-chat    [path/to/session.jsonl -o out.txt]   # default: newest for cwd
```

Profiles: `code` (default, generic), `datarim` (artifacts schema-aware),
`social` (posts), `write` (boilerplate). Default provider per profile is in
`~/.config/coworker/profiles.yaml` — for cost-sensitive generation prefer
`--provider deepseek` (≈14× cheaper output than Moonshot).

After `coworker write`: read the output and edit judgment-parts. **Never
accept blindly.**

## File-type policy

`coworker ask` accepts only `.md`, `.markdown`, `.txt` files by default.
Passing any other extension (`.py`, `.ts`, `.js`, `.rs`, `.go`, `.sh`, …)
exits `6` with:

```text
ERROR: file 'X' (extension '.py') is not in the allowed list (.markdown, .md, .txt).
Use Claude's Read tool for code analysis, or pass --allow-code / COWORKER_ALLOW_CODE=1 to override.
```

To delegate **code** reads (>600 lines / ≥3 files), opt in explicitly with
ONE of:

```bash
coworker ask --allow-code --paths src/foo.py src/bar.py --question "..."
# or:
COWORKER_ALLOW_CODE=1 coworker ask --paths src/foo.py --question "..."
```

The override demotes the block to a per-file `WARNING (override)` line on
stderr and proceeds. Do not retry after `exit 6` — use the flag from the
first call when the trigger fires on code files. Prefer the explicit
`--allow-code` flag over the env var so the override stays visible in
shell history.

`coworker write --context <path>` and `--target <path>` accept any
extension (no allowlist on write paths).

## RTK plugin (opt-in)

`coworker rtk` is an opt-in token-reduction plugin backed by the local
`rtk` binary ([github.com/Arcanada-one/rtk](https://github.com/Arcanada-one/rtk)).
Default-off — installing coworker does NOT activate RTK; explicit opt-in
required.

```text
coworker rtk install   # OS-specific install instructions (macOS/Linux/Windows)
coworker rtk enable    # add idempotent hook to ~/.claude/settings.json
coworker rtk disable   # remove hook
coworker rtk status    # binary path/version + hook on/off
```

Enable when bulk reads exceed ~5k tokens regularly (logs, code dumps,
long diffs). Skip for short tasks — overhead exceeds savings. Full
operator-facing reference: `documentation/infrastructure/Coworker.md`
§ RTK plugin (opt-in).

## Do NOT delegate

- Tasks under ~2 000 tokens (overhead not worth it).
- Debugging, root-cause analysis, race conditions, safety-critical logic.
- Architectural decisions and trade-offs.
- When exact line numbers are needed for `Edit` (coworker summaries lose
  them).
- Reasoning about user intent.

## Failure modes

If the chosen provider's API key is unset / out of balance, scripts fail
loudly — fall back to native `Read` for that turn only. Switch provider
with `--provider` if one is down.

## Runtime enforcement

A per-machine hook script (`~/.local/bin/coworker-hook-guard`, canonical
source `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/coworker-hook-guard.sh"`) inspects every `PreToolUse`
event and emits `permissionDecision=deny` when the agent attempts a direct
`Read`/`Write`/`Bash` (Claude) or `view`/`apply_patch`/`shell` (Codex) call
that violates the rules above. The hook is registered via
`~/.claude/settings.json` (Claude) or `~/.codex/hooks.json` (Codex,
operator-maintained per machine — see
`docs/how-to/codex-cli-coworker-hooks.md`).
