# Fleet Hook Sync Runbook

> **Created:** TUNE-0537 (2026-07-30)
>
> How to verify and synchronise per-machine hook registration across the
> Datarim fleet after a hook update lands in the canonical repo.

## Background

Datarim ships per-machine hook scripts that enforce runtime policy:

- `coworker-hook-guard` — delegation gating (Read/Write/Bash + SessionStart)
- `datarim-exec-guard` — execution-host gating (Bash)
- `branch-integration-guard` — branch-merge gating (Bash)
- `rtk-signal-guard.sh` — RTK token-reduction guard (Bash)

These are **per-machine artefacts**. A fix that lands only in `git` changes
nothing on any machine. The update path is:

```
canonical repo (git pull) → install.sh --with-claude --with-codex → hook symlink updated → settings.json re-read → active
```

The `install.sh` script links each hook into `~/.local/bin/` and registers
the Claude Code hook path in `~/.claude/settings.json`. Registration and
binary-update are independent steps — both must succeed.

## Pre-flight: verify current state

On each fleet machine (Mac, DEVS, any future runner):

```bash
# 1. Is the hook binary present and a symlink to the canonical repo?
ls -la ~/.local/bin/coworker-hook-guard

# 2. Is the hook registered in Claude Code settings?
grep -c "coworker-hook-guard" ~/.claude/settings.json
# Expected: >= 1 (should be 1 for most installs; Mac may have 2)

# 3. Is the hook registered in Codex CLI settings?
grep -c "coworker-hook-guard" ~/.codex/hooks.json 2>/dev/null || echo "codex hooks not configured"

# 4. Does the hook file match the canonical source?
diff ~/.local/bin/coworker-hook-guard "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/coworker-hook-guard.sh"
# Expected: no diff (symlink → same inode, so diff is empty)
```

## Sync procedure

After a hook change is merged to `main` in the Datarim framework repo:

```bash
# 1. Pull latest framework
cd "${DATARIM_RUNTIME:-$HOME/.claude}" || exit 1
git pull

# 2. Re-run install to update hook symlinks (idempotent)
./install.sh --with-claude --with-codex

# 3. Verify binary is the updated version
grep "TUNE-0537" ~/.local/bin/coworker-hook-guard && echo "Updated" || echo "STALE"

# 4. Verify registration parity
grep -c "coworker-hook-guard" ~/.claude/settings.json
# If 0: re-run install.sh OR manually add the hook entry
```

## Registration verification (per-machine)

Hooks are registered in `~/.claude/settings.json` under `hooks.PreToolUse`
and `hooks.SessionStart`. The canonical registration for all active guards:

```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Read|Write|Bash", "command": "/home/<user>/.local/bin/coworker-hook-guard"},
      {"matcher": "Bash", "command": "/home/<user>/.local/bin/rtk-signal-guard.sh"},
      {"matcher": "Bash", "command": "/home/<user>/.local/bin/datarim-exec-guard"},
      {"matcher": "Bash", "command": "/home/<user>/.local/bin/branch-integration-guard"}
    ],
    "SessionStart": [
      {"command": "/home/<user>/.local/bin/coworker-hook-guard"}
    ]
  }
}
```

**Verification on any machine:**

```bash
# Check all 4 guard binaries
for g in coworker-hook-guard branch-integration-guard rtk-signal-guard.sh datarim-exec-guard; do
  [ -f "$HOME/.local/bin/$g" ] && echo "OK: $g" || echo "MISSING: $g"
done

# Check registration
jq '.hooks.PreToolUse | length' ~/.claude/settings.json
# Expected: >= 4
```

**Symlink from canonical repo:**

```bash
# datarim-exec-guard must be symlinked from the framework repo (shipped in TUNE-0519)
ln -sf "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/datarim-exec-guard.sh" ~/.local/bin/datarim-exec-guard

# other guards are linked by install.sh
```

## Registration history (DEVS)

| Date | Event |
|------|-------|
| 2026-07-30 (TUNE-0537 merge) | Hook binaries present, settings.json had ZERO hooks registered |
| 2026-07-30 08:45 UTC | Backed up settings.json, registered all 4 PreToolUse + 1 SessionStart hooks via `jq`, verified harmless Bash passes, datarim-exec-guard symlinked |

**Root cause:** `install.sh` does not register hooks — it only links binaries.
Registration is a per-machine step. The fleet-hook-sync runbook is the
canonical reference for this step.

## Hook update does NOT require agent restart

Claude Code reads `settings.json` at session start. A hook binary update
(hot-swapped via symlink) takes effect on the next `PreToolUse` event —
no restart needed. Registration changes require a new session.

## Known gaps

- **Cursor IDE** — advisory-only rules (`.cursor/rules/`), no hook mechanism.
  Hook enforcement is Claude Code / Codex CLI only.
- **Codex CLI registration** — `~/.codex/hooks.json` is operator-maintained,
  not automated by install.sh for all hook types. Verify manually.
