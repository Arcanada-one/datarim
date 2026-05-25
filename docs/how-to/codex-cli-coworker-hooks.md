# Codex CLI — coworker hook setup (per-machine)

Codex CLI (`codex` v0.133+) honours `~/.codex/hooks.json` for `PreToolUse`
and `SessionStart` events. Datarim installer (`install.sh fanout_runtime`)
fans out the canonical hook script as a symlink, but does NOT touch
`~/.codex/hooks.json` because operators frequently maintain it under their
own dotfiles repo. This runbook documents the manual edit each operator
must apply once per machine to make Codex actually fire the hook on its
native tools.

## Source: TUNE-0303 (2026-05-25)

Decision D2 — `~/.codex/hooks.json` operator-maintained per machine,
symmetric to `~/.claude/settings.json`. Installer never overwrites.

## Steps

1. Verify `install.sh` has produced the symlink:

    ```bash
    readlink ~/.local/bin/coworker-hook-guard
    # → /…/Projects/Datarim/code/datarim/dev-tools/coworker-hook-guard.sh
    ```

   If missing, run `./install.sh --with-codex` from the Datarim repo.

2. Edit `~/.codex/hooks.json` so the matcher covers both Claude and Codex
   tool names:

    ```json
    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Read|Write|Bash|shell|apply_patch|view",
            "hooks": [
              {
                "type": "command",
                "command": "~/.local/bin/coworker-hook-guard",
                "timeout": 5
              }
            ]
          }
        ],
        "SessionStart": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "~/.local/bin/coworker-hook-guard",
                "timeout": 6
              }
            ]
          }
        ]
      }
    }
    ```

   Codex native tools (`shell`, `apply_patch`, `view`) are the names the
   PreToolUse matcher sees — confirmed via `~/.codex/logs_2.sqlite` and
   Codex `tool_name` propagation.

3. Restart any running codex sessions so the new matcher takes effect
   (`hooks.json` is read at session start).

4. Smoke-test the matcher in one session:

    ```bash
    seq 1 500 > /tmp/long.txt
    codex exec --skip-git-repo-check 'view /tmp/long.txt' --json 2>&1 | \
        grep -E 'permissionDecision|deny|400' | head -5
    ```

   Expected: a `permissionDecision=deny` envelope from the hook + Codex
   refuses the call.

5. Verify the hook caused real delegation in `coworker stats`:

    ```bash
    coworker stats --since 30m --by profile | grep -E '^codex\s'
    ```

   At least one new `codex` call should appear after the smoke session.

## Troubleshooting

- **`hook/started` never appears in `~/.codex/logs_2.sqlite`** — the
  matcher likely does not cover the native tool name. Re-check step 2.
- **`shell_environment_policy.set` strips `PATH`** — Codex may not find
  the hook binary. Confirm `command -v ~/.local/bin/coworker-hook-guard`
  resolves inside the codex sandbox.
- **`trusted_hash` failure** — Codex requires the hook command to be
  trusted. Add the absolute path of the resolved symlink target to
  `~/.codex/config.toml` `[trusted_commands]` if your codex build
  enforces hash verification.
- **Hook fires but no `coworker` call follows** — Codex respects the
  `deny` envelope but the agent may need explicit MANDATORY-delegation
  instructions visible at session start. Re-run
  `./install.sh --with-codex` so `~/.codex/AGENTS.override.md` carries
  the `MANDATORY delegation (Codex runtime)` block at the top.

## Related

- Canonical hook source: `dev-tools/coworker-hook-guard.sh`
- Mandate text: `templates/coworker-delegation-fragment.md`
- bats coverage: `tests/test-coworker-hook-guard-codex.bats`,
  `tests/test-coworker-hook-guard-head-blind.bats`
- Source task: TUNE-0303 (`datarim/tasks/TUNE-0303-task-description.md`)
- Parent epic: TUNE-0296 Codex CLI parity
