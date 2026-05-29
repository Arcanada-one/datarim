---
name: file-sync-config
description: Pre-flight checklist + ignore patterns for file-sync (Syncthing/rclone/rsync/Dropbox/iCloud) — protection for git working trees and venv/build directories.
current_aal: 1
target_aal: 2
---

# File-Sync Configuration — Pre-Flight Checklist

## When To Use

Load this skill before configuring ANY two-way file-sync between multiple hosts:

- Syncthing folder setup
- rclone bisync
- Dropbox / iCloud / Google Drive shared folder
- rsync periodic job
- Disk Arcana sync (planned)
- Any custom sync layer

**Do NOT load** this skill for one-way backup or CI artifact transfer — the risk model is different.

## Why It Matters (founding incident)

Founding incident (2026-04-25): the first `.stignore` for Syncthing had 28 patterns and did not cover `.venv`, `__pycache__`, `target/`, `*.db`, and did not exclude nested git repositories entirely. The result:

- 1 materialised sync-conflict in production (`AI_agents/Email Agent/CLAUDE.md`) — deploy documentation would have been lost if Syncthing had not preserved a `.sync-conflict` copy.
- 60+ sync-conflict files accumulated in the vault over one week.
- 14 git repositories with different checked-out branches synced as plain working trees → working-tree drift between the Mac and the DEV box.
- Cross-platform breakage risk: Python `.venv` (macOS Mach-O) vs Linux ELF binaries.

After expanding the pattern list from 28 → 66, the file count dropped from 40,361 → 2,206 (−95%).

## Pre-Flight Inventory (MANDATORY before sync setup)

Before turning sync on, **run `find` against every class of problematic files** on the source host:

```sh
SYNC_ROOT=/Users/me/myvault   # or another source root

# Vendored / build artifacts
find "$SYNC_ROOT" -maxdepth 6 \( \
  -name "node_modules" -o \
  -name ".venv" -o \
  -name "venv" -o \
  -name "__pycache__" -o \
  -name "target" -o \
  -name ".next" -o \
  -name ".turbo" -o \
  -name ".nuxt" -o \
  -name ".cache" -o \
  -name ".parcel-cache" -o \
  -name "coverage" -o \
  -name ".nyc_output" -o \
  -name "dist" -o \
  -name "build" -o \
  -name ".build" -o \
  -name "DerivedData" -o \
  -name ".pytest_cache" -o \
  -name ".mypy_cache" -o \
  -name ".ruff_cache" \
\) -type d 2>/dev/null

# Nested git repositories (CRITICAL)
find "$SYNC_ROOT" -maxdepth 6 -name ".git" -type d 2>/dev/null

# Local DB / state files
find "$SYNC_ROOT" -maxdepth 6 \( \
  -name "*.db" -o \
  -name "*.sqlite" -o \
  -name "*.sqlite3" -o \
  -name "*.duckdb" -o \
  -name "*.db-journal" \
\) -type f 2>/dev/null

# Compiled binaries (cross-platform unsafe)
find "$SYNC_ROOT" -maxdepth 6 \( \
  -name "*.so" -o \
  -name "*.dylib" -o \
  -name "*.dll" -o \
  -name "*.exe" \
\) -type f 2>/dev/null

# IDE / OS junk (lower risk but clutters the index)
find "$SYNC_ROOT" -maxdepth 6 \( \
  -name ".idea" -o \
  -name ".vscode" -o \
  -name ".DS_Store" -o \
  -name "Thumbs.db" \
\) 2>/dev/null
```

**Every class the inventory surfaces MUST be added to your ignore patterns BEFORE the first sync.**

## Decision Tree: Sync Working Trees vs Git Pull

For every `.git/` directory inside the sync root, answer one question:

```
Does the SECOND node have live edits, agents, or production runtime in this repo?
├── YES → DO NOT sync the working tree.
│        Exclude the entire /path/to/repo from sync.
│        Use a `git pull` cron on the second node
│        (see the arcanada-pull.sh pattern).
└── NO  → The working tree can be synced (read-only side).
         Still exclude .git/ — every node keeps its own commit history.
```

**Default to YES** — almost always the second node will eventually become "active" (a new agent appears, a deploy script lands, a manual edit happens). Over-protection is cheaper than recovery.

## Reusable .stignore Template (Syncthing)

```gitignore
# === CRITICAL: project source code (separate git repos) ===
# Each node keeps its own checked-out branch and updates via
# independent `git pull`. Never sync these via file-sync — otherwise
# working-tree conflicts break the agents.
/Projects/*/code
/Projects/Datarim/sources
/Projects/Rules of Robotics/Code

# === CRITICAL: AI agents with their own git/venv ===
/AI_agents/Email Agent
/AI_agents/Screen reader
/AI_agents/Remove-Watermark
/AI_agents/Agent Dreamer

# === Workflow / runtime state — host-specific ===
.git
.dreamer
.meta
.claude
.githooks

# === Datarim pre-overwrite backups — host-local, MUST NOT sync ===
# The KB backup primitive writes pre-overwrite copies under datarim/.backups/.
# They are recovery ground-truth for ONE host's agent↔agent races; syncing
# them across machines would spawn the very .sync-conflict-* files they exist
# to protect against. Keep them out of every sync set (they are also gitignored
# by the wholesale datarim/ ignore).
datarim/.backups
.backups

# === Build / deps (cross-platform unsafe) ===
node_modules
dist
build
.next
.turbo
.nuxt
.cache
.parcel-cache
coverage
.nyc_output
target

# === Python environments / caches ===
.venv
venv
__pycache__
*.pyc
.pytest_cache
.mypy_cache
.ruff_cache

# === iOS/macOS Swift build artifacts ===
.build
DerivedData
*.xcuserstate

# === Compiled binaries (host-specific) ===
*.so
*.dylib
*.dll
*.exe
*.o
*.a

# === DB / state files (local-only) ===
*.db
*.sqlite
*.sqlite3
*.duckdb
*.db-journal
*.db-shm
*.db-wal

# === Misc temp / OS / secrets ===
*.tmp
*.log
.env
.env.*
.env*
.DS_Store
Thumbs.db
.Spotlight-V100
.Trashes
.fseventsd
```

## Pattern Syntax Cheat-Sheet

### Syncthing (`.stignore`, applied via `POST /rest/db/ignores`)

| Pattern | Matches |
|---|---|
| `node_modules` | every `node_modules/` directory at any depth |
| `/Projects/*/code` | path-anchored (`/` prefix) — only this exact path |
| `*.db` | every `.db` file at any depth |
| `.git/**` | everything inside `.git` (but not the directory itself) |
| `(?d)pattern` | delete the file if it has already been synced (use with care) |
| `(?i)pattern` | case-insensitive match |
| `!important.log` | negation — do NOT ignore (override of a previous rule) |

Source: https://docs.syncthing.net/users/ignoring.html

### rclone (`--exclude` or `.rcignore`)

| Pattern | Matches |
|---|---|
| `node_modules/` | trailing `/` = directories only |
| `**/*.db` | `**` = recurse through directories |
| `/path/to/exclude/**` | path-anchored with leading `/` |

### rsync (`--exclude=` or `--exclude-from=file`)

| Pattern | Matches |
|---|---|
| `node_modules` | does not distinguish file from directory |
| `/relative/path` | relative to the start directory |
| `**/*.tmp` | recursive glob |

### gitignore (for context)

| Pattern | Matches |
|---|---|
| `node_modules` | directory or file with this name at any depth |
| `/node_modules` | match only at the repo root |
| `**/build` | every `build` directory anywhere |

## Workflow for git-managed repos (when file-sync is excluded)

If you excluded `/Projects/*/code` from sync, the second node needs an alternate update mechanism:

1. **Cron `git pull` script** — recommended pattern: `documentation/infrastructure/scripts/arcanada-pull.sh`:
   - `git fetch` upstream.
   - Skip if local == remote.
   - Skip if the branch is not `main` / `master` (an agent is on a feature branch).
   - Stash local edits → ff-only pull → fall back to merge → fall back to a CLI Claude conflict resolver → unresolved-state alert via Ops Bot.
   - Pop the stash → if conflict, invoke Claude again.

2. **CI/CD self-hosted runner** — a GitHub Actions runner on the second node pulls when `main` is pushed (event-driven instead of cron polling).

3. **Manual** — the user runs `git pull` themselves when needed. Suitable for rarely-updated repos.

## Compliance Check (for `/dr-compliance` infrastructure tasks)

When configuring file-sync, verify each item:

- [ ] Pre-flight inventory completed (`find` for every class).
- [ ] Every class the inventory surfaced is in the ignore patterns.
- [ ] Every nested `.git/` directory is either fully excluded or explicitly documented as a "read-only mirror".
- [ ] Cross-platform binary classes (`.venv`, `target`, `*.so` / `*.dylib` / `*.dll`) are excluded if the sync spans different operating systems.
- [ ] DB files (`*.db`, `*.sqlite`) are excluded (they are host-local state).
- [ ] Lockdown settings are applied (`globalAnnounce=false`, no public discovery, transport-only-tailnet).
- [ ] A configuration backup is stored (`config.xml.pre-{TASK-ID}`).
- [ ] The runbook is documented (topology, ops, rollback).
- [ ] A smoke test ran in both directions (file flow source → target and target → source).

## Related

- `Areas/Architecture/file-sync-policy.md` (ADR) — vault-level convention for the Arcanada ecosystem.
- `Areas/Infrastructure/Syncthing.md` — Syncthing deployment runbook.
- `Areas/Infrastructure/scripts/arcanada-pull.sh` — git-pull cron with the CLI Claude conflict resolver.
- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cli-conflict-resolver-prompt.md` — reusable Claude prompt for conflict resolution.
