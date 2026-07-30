# Fleet Hook Sync Runbook

> **Created:** TUNE-0537 (2026-07-30)
>
> How to verify and synchronise per-machine hook registration across the
> Datarim fleet after a hook update lands in the canonical repo.

## Background

Datarim ships per-machine hook scripts that enforce runtime policy:

- `coworker-hook-guard` — delegation gating (Read/Write/Bash)
- `datarim-exec-guard` — execution-host gating
- `branch-integration-guard` — branch-merge gating

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

## Registration asymmetry (DEVS)

As of TUNE-0537 (2026-07-30):

| Machine | Binary present | Registered in settings.json |
|---------|---------------|---------------------------|
| Mac     | Yes (symlink) | 2 occurrences |
| DEVS    | Yes (symlink) | **0 occurrences** — hook installed but NOT registered |

**Impact:** On DEVS, the hook binary exists but Claude Code never invokes it
because it is not listed in `~/.claude/settings.json`. The hook's policy
enforcement is **absent** on DEVS.

**Fix:** Run `install.sh --with-claude` on DEVS. The `setup_coworker_hook_symlink()`
step is idempotent (binary symlink is already correct), and the
`sync_claude_coworker_fragment` step handles registration. If registration is
still absent after install, add the hook entry manually per the install.sh
template.

## Hook update does NOT require agent restart

Claude Code reads `settings.json` at session start. A hook binary update
(hot-swapped via symlink) takes effect on the next `PreToolUse` event —
no restart needed. Registration changes require a new session.

## Known gaps

- **Cursor IDE** — advisory-only rules (`.cursor/rules/`), no hook mechanism.
  Hook enforcement is Claude Code / Codex CLI only.
- **Codex CLI registration** — `~/.codex/hooks.json` is operator-maintained,
  not automated by install.sh for all hook types. Verify manually.
