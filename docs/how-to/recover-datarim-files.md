# Recover Datarim Knowledge-Base Files

**Audience:** operators whose `datarim/` knowledge-base file was zeroed, truncated, corrupted, or lost. 
**Introduced in:** v2.26.0

This document is a **how-to** - a set of concrete recovery recipes. It is not a tutorial or a reference; perform steps in the order that best matches your situation.

---

## First: stop and assess

**Stop writing to the repo.** Every new write may overwrite a pre-overwrite backup that could have saved you.

1. Identify which file is damaged. The critical files under `datarim/` are:
 - `datarim/backlog.md`
 - `datarim/backlog-archive.md`
 - `datarim/tasks.md`
 - `datarim/activeContext.md`
 - `datarim/progress.md`
 - `datarim/history/` ledger files (`evolution-log.md`, `activity-log.md`, `patterns.md`)

2. Note that almost all `datarim/` files are **gitignored** (the directory is listed in `.gitignore`). 
 A `git checkout` will **not** recover `backlog.md`, `tasks.md`, etc. 
 The only files under `datarim/` that **are** committed are the `datarim/history/` ledgers, re-included by the `.gitignore` negation block:

 ```gitignore
 /datarim/*
 !/datarim/history/
 !/datarim/history/**
 ```

 Both negation lines are required - git never descends into a directory excluded with a trailing slash, so `/datarim/` must first be rewritten to the glob form `/datarim/*` before `!/datarim/history/` can take effect.

3. If the damage happened *just now* - before any further writes - you likely still have a backup under `datarim/.backups/` (see below). **Do not touch that directory until you read section Restore from a pre-write backup.**

---

## Per-file sources of truth (recovery priority order)

| File | Recovery sources in priority order |
|---|---|
| `backlog.md` | (1) `datarim/.backups/backlog.md.*.bak` (newest first) - (2) `.sync-conflict-*` siblings - (3) reconstruct from `datarim/tasks/*-init-task.md` artefacts - (4) session transcripts |
| `backlog-archive.md` | (1) `.backups/backlog-archive.md.*.bak` - (2) `.sync-conflict-*` - (3) reconstruct from `documentation/archive/<area>/archive-*.md` frontmatter - (4) session transcripts |
| `tasks.md` | (1) `.backups/tasks.md.*.bak` - (2) `.sync-conflict-*` - (3) reconstruct from `datarim/tasks/*-task-description.md` and `*-init-task.md` artefacts - (4) session transcripts |
| `activeContext.md` | (1) `.backups/activeContext.md.*.bak` - (2) `.sync-conflict-*` - (3) session transcripts |
| `progress.md` | (1) `.backups/progress.md.*.bak` - (2) `.sync-conflict-*` - (3) session transcripts |
| `datarim/history/` ledgers | **First source: `git checkout` / `git log`** - they are committed. Then `.backups/`, then `.sync-conflict-*` |

> **Why are the ledgers recoverable via git and the others not?** 
> The `.gitignore` negation block (`/datarim/*` + `!/datarim/history/` + `!/datarim/history/**`) re-includes those files so they are version-controlled. All other `datarim/` files are explicitly ignored.

---

## Restore from a pre-write backup

The backup primitive (`scripts/lib/kb-backup.sh`) acts automatically: every overwrite of a critical workflow file (`backlog.md`, `backlog-archive.md`, `tasks.md`, `activeContext.md`, `progress.md`) via the **Write** tool or a Bash redirect (`>`, `>>`, `tee`) is intercepted by the `PreToolUse` hook (`dev-tools/coworker-hook-guard.sh`). Before the write proceeds, the existing content is copied to:

```
datarim/.backups/<basename>.<ISO-timestamp>.bak
```

Rotation keeps the most-recent 10 copies per basename (configurable via `DR_KB_BACKUP_KEEP`).

### Steps

```sh
# 1. Go to the repo root (the parent of datarim/).
cd /path/to/repo-root

# 2. List backups for the damaged file, newest first.
ls -t datarim/.backups/backlog.md.*.bak | head -5

# 3. Inspect the newest one.
cat "$(ls -t datarim/.backups/backlog.md.*.bak | head -1)"
# Or diff it against what's currently on disk:
diff -u datarim/backlog.md "$(ls -t datarim/.backups/backlog.md.*.bak | head -1)"

# 4. If it looks correct, copy it back.
cp "$(ls -t datarim/.backups/backlog.md.*.bak | head -1)" datarim/backlog.md
```

**Important notes about the backup directory:**

- `datarim/.backups/` is **gitignored** - it will never be committed.
- It is also **excluded from all file-sync** (Syncthing, rclone, etc.) - see the `file-sync-config` skill. The backups are **host-local recovery ground-truth**. They do not replicate across machines.
- Permissions are `chmod 700` on the directory and `chmod 600` on each backup file (umask 077).

---

## Restore from a file-sync conflict copy

Syncthing and iCloud write conflict siblings named `<basename>.sync-conflict-<timestamp>-<hash>.md`.

```sh
# Find conflict copies under datarim/.
find datarim/ -name "*.sync-conflict-*" -type f

# Diff candidate with the damaged file.
diff -u datarim/backlog.md datarim/backlog.sync-conflict-20260426-123456-abc.md

# If it's the content you need, restore it.
cp datarim/backlog.sync-conflict-20260426-123456-abc.md datarim/backlog.md
```

After restoring, you may wish to remove the conflict sibling to avoid confusion:

```sh
rm datarim/backlog.sync-conflict-20260426-123456-abc.md
```

---

## Repair structural drift with datarim-doctor

If the damage goes beyond a single file - for example, the directory layout under `datarim/` has drifted (legacy `datarim/docs/` still present, missing `datarim/history/`, broken `.gitignore`) - run the doctor:

```sh
# --root expects the REPO ROOT (parent of datarim/), NOT the datarim/ directory itself.
datarim-doctor.sh --root=/path/to/repo-root --fix
```

Without `--fix` the doctor only reports drift. With `--fix` it:

- Migrates legacy `datarim/docs/` ledgers to `datarim/history/`.
- Relocates ADRs found in `datarim/` to `documentation/architecture/`.
- Writes the `.gitignore` negation block for `datarim/history/`.
- Takes its own umask-077 tarball backup before any write.

If you only need the ledger migration (the most common drift pattern):

```sh
datarim-doctor.sh --root=/path/to/repo-root --fix --scope=history
```

If the doctor detects an invariant failure after a `--fix` write, it restores its own tarball backup automatically and reports the error. You are never left with a half-fixed repo.

---

## Prevention

Two mechanisms protect against future loss.

### Pre-overwrite backups (automatic)

Every overwrite of the five critical workflow files - `backlog.md`, `backlog-archive.md`, `tasks.md`, `activeContext.md`, `progress.md` - is intercepted **before** the new content lands. The existing copy is saved to `datarim/.backups/` as described above. This is active by default in any environment whose `PreToolUse` hook is `dev-tools/coworker-hook-guard.sh`.

The `datarim/history/` ledgers are **not** in the backup allowlist - they are protected differently, by being committed to git (see section Per-file sources of truth). `git` is their backup.

### Unified path resolver (avoids nested drifts)

The primitive `scripts/lib/resolve-datarim-root.sh` enforces a single convention: `--root` always means the **repo root** (the parent of `datarim/`). Every script (`kb-backup.sh`, `datarim-doctor.sh`, the hook guard) uses the same resolver. This prevents the old class of bug where a tool was pointed at `datarim/` and created `datarim/datarim/` - the backup directory would then be in the wrong place and the next restore would fail silently.

If you have ever seen a `datarim/datarim/` path (e.g. `datarim/datarim/snapshots/`), that was a previous-generation drift. The unified resolver and the `assert_not_nested_datarim` guard now prevent any tool from creating one. A leftover nested directory is safe to remove manually once you have confirmed it holds no unique content (`diff -r` it against the canonical `datarim/` location first).

---

## Limitations

- **Best-effort Bash-redirect detection.** The `PreToolUse` hook catches `> file`, `>> file`, and `tee file` when the destination is a literal string. Obfuscated redirects - especially those built by runtime variable interpolation (`eval`, `$path`, computed paths) - are **not** intercepted. If you or an agent uses `eval "cat ... > \$dest"`, no backup is taken.
- **FAT / exFAT filesystems.** On these platforms, `chmod` does not apply and `atomic rename` degrades to a copy-then-delete. The backup may be left in an inconsistent state if the process is killed mid-rename, but the fail-soft contract still holds: the backup attempt never blocks the write it precedes.
- **Backups are not replicated.** Because `datarim/.backups/` is sync-excluded, each host has its own backup history. Recovering on a second machine requires either routing the recovery through git (for committed ledgers) or reconstructing from the other sources listed in the priority table above.