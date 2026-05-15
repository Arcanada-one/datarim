# Symlink-default Operating Model

> Since v1.17.0, `install.sh` defaults to symlink mode (the `symlink-default`
> operating model). Copy mode is the documented fallback for filesystems
> without symlink support. This document is the operating-model reference.

## Why symlinks

Symlink-default install keeps `~/.claude/{agents,skills,commands,templates}/`
pointing into the cloned Datarim repo. The result:

- **Single source of truth.** The repo is the only place where runtime files
  live. There is no second copy in `~/.claude/` to drift away from upstream.
- **Instant refresh.** `git pull` updates every skill, agent, command, and
  template the next time a runtime invokes them — no install step, no copy
  step, no merge.
- **Live edits flow back.** Editing a skill in `~/.claude/skills/foo.md`
  edits the repo file directly; the change can be inspected with `git diff`
  and shipped as a PR.
- **No drift surface.** `check-drift.sh` becomes a no-op assertion rather
  than a routine cleanup tool.

## How `install.sh` detects support

The installer probes for symlink support before choosing a mode:

```bash
# noshellcheck-extract
# inside install.sh (simplified)
if ln -s /tmp/.symlink-probe-target /tmp/.symlink-probe-link 2>/dev/null; then
    rm -f /tmp/.symlink-probe-link
    INSTALL_MODE=symlinks
else
    INSTALL_MODE=copy
fi
```

If the probe fails (FAT, exFAT, certain NTFS mounts, sandboxes that disallow
`symlinkat(2)`), the installer falls back to copy mode automatically.

## Installation modes

### Default — symlink

```bash
./install.sh                 # auto-detect; symlink if supported
./install.sh --symlinks      # force symlink mode (fail if unsupported)
```

After installation, each scope under `~/.claude/` is a symlink into the
cloned repo:

```text
~/.claude/skills      -> /path/to/datarim/skills
~/.claude/agents      -> /path/to/datarim/agents
~/.claude/commands    -> /path/to/datarim/commands
~/.claude/templates   -> /path/to/datarim/templates
```

### Fallback — copy

```bash
./install.sh --copy
```

Copy mode replicates files into `~/.claude/` and leaves the repo untouched.
Drift is then expected and `check-drift.sh` becomes the recommended cadence.

## Migration from copy mode

If `~/.claude/` already holds copied files from an older install:

```bash
# noshellcheck-extract
# 1. Backup the existing directory
mv ~/.claude ~/.claude.bak-$(date +%Y%m%d)

# 2. Re-run install in symlink mode
cd /path/to/datarim
./install.sh --symlinks

# 3. Compare for any local customisation worth preserving
diff -r ~/.claude.bak-*/skills    /path/to/datarim/skills
diff -r ~/.claude.bak-*/agents    /path/to/datarim/agents
diff -r ~/.claude.bak-*/commands  /path/to/datarim/commands
diff -r ~/.claude.bak-*/templates /path/to/datarim/templates
```

Anything worth keeping should be migrated upstream as a PR rather than left
in the local copy.

## Verification

```bash
./scripts/check-drift.sh     # exits 0 when every scope is a symlink at the repo
ls -la ~/.claude/skills      # confirm `->` arrow pointing at the repo path
```

## Limitations

- **FAT / exFAT filesystems** do not support `symlinkat(2)`; the installer
  falls back to copy mode automatically.
- **Sync tools that dereference symlinks** (rclone, certain Dropbox modes)
  will materialise the symlink target into the cloud destination. See the
  Arcanada-ecosystem File Sync Policy for the recommended exclusion patterns.
- **CI runner images** that build the framework into a container image need
  a deliberate copy step — the symlink would point outside the image
  filesystem.
- **Windows native** (non-WSL) requires either Developer Mode or admin
  privileges to create symlinks; copy mode is recommended on Windows
  outside WSL.

## See also

- [`README.md`](../README.md) § Installation — entry-point overview.
- [`docs/getting-started.md`](getting-started.md) — first-run walkthrough.
- [`docs/release-process.md`](release-process.md) — how releases ship and
  how the installer pins to a version.
