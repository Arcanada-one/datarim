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

**Out-of-box `rtk` vs `coworker rtk` plugin — why the plugin matters.**
The standalone `rtk` binary, when activated as a global git/shell hook
without the coworker passthrough allowlist, produces measurable
token savings on bulk reads but also drops or rewrites the textual
markers that Claude Code and Codex CLI rely on to confirm command
completion. Measured impact on macOS (upstream issue
[rtk-ai/rtk#2121](https://github.com/rtk-ai/rtk/issues/2121)): `git
status` output grew by +108% (the marker bloated rather than
shrank), `git log --oneline -50` by +6924%, and the `git push`
completion marker was lost entirely on some repos, making the agent
think the push had not happened. The `coworker rtk` plugin guards
against this by wrapping `rtk` invocations in a passthrough
allowlist for signal-bearing commands (`git status`, `git log`,
`git push`, `gh release`, `gh pr`, and 8 others by default) while
still applying bulk-read economy to log dumps, file content reads,
and `git diff` outputs. The plugin also installs a Codex CLI shim so
multi-runtime parity is preserved. Operators who want token-economy
benefits should enable RTK via the plugin (`coworker rtk install`
+ `coworker rtk enable`) rather than wiring the raw binary into
`~/.claude/settings.json` directly. The default 13-pattern
passthrough store and CRUD workflow are documented in
`docs/rtk-plugin.md` § Signal/bulk passthrough.

## Do NOT delegate

- Tasks under ~2 000 tokens (overhead not worth it).
- Debugging, root-cause analysis, race conditions, safety-critical logic.
- Architectural decisions and trade-offs.
- When exact line numbers are needed for `Edit` (coworker summaries lose
  them).
- Reasoning about user intent.
- **Appending to an existing file via `coworker write --target Y` without
  `--append`.** Bare `coworker write --target Y` truncate-writes Y
  (`Path.write_text()`, Python `'w'` mode). A spec like `--spec "append
  section X to file Y" --target Y` overwrites Y with only the new section
  and destroys everything else (frontmatter, prior sections). Since
  coworker v0.4.0 the canonical fix is the `--append` flag:
  `coworker write --append --target Y --spec "..."` — opens Y in `'a'`
  mode, inserts a separator newline if Y's tail is non-terminated, falls
  back to write when Y does not yet exist, and is mutually exclusive with
  `--stdout`. Reach for the legacy workarounds only when the target's
  byte-exact tail matters: (1) `--stdout` and concatenate captured body
  manually; (2) feed Y as `--context` and write to a fresh `--target`;
  (3) native surgical edit.

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
