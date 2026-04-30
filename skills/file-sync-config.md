---
name: file-sync-config
description: Pre-flight checklist + ignore patterns для file-sync (Syncthing/rclone/rsync/Dropbox/iCloud) — защита git working trees и venv/build.
---

# File-Sync Configuration — Pre-Flight Checklist

## When To Use

Загружай этот skill перед настройкой ЛЮБОГО двустороннего файлового синка между несколькими хостами:

- Syncthing folder setup
- rclone bisync
- Dropbox/iCloud/Google Drive shared folder
- rsync периодический job
- Disk Arcana sync (DISK-0011 future)
- Любой custom sync layer

**НЕ загружай** для одностороннего бэкапа или CI artifact transfer — там risk model другой.

## Why It Matters (founding incident)

INFRA-0026 (2026-04-25): первая версия `.stignore` для Syncthing содержала 28 patterns и не покрывала `.venv`, `__pycache__`, `target/`, `*.db`, плюс не исключала вложенные git-репо целиком. Результат:

- 1 материализованный sync-conflict в production (`AI_agents/Email Agent/CLAUDE.md`) — потеряли бы deploy-документацию если бы Syncthing не сохранил .sync-conflict копию.
- 60+ sync-conflict файлов накопилось в vault за неделю.
- 14 git-репо с разными checkout-ветками синкались как plain working trees → working tree drift между mac и DEV.
- Cross-platform breakage риск: Python `.venv` (macOS Mach-O) vs Linux ELF binaries.

После расширения patterns с 28 → 66 файловый счёт упал с 40,361 → 2,206 (−95%).

## Pre-Flight Inventory (MANDATORY before sync setup)

Прежде чем включать sync, **запусти `find` по каждому классу проблемных файлов** на источнике:

```sh
SYNC_ROOT=/Users/me/myvault   # или другой источник

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

# Vложенные git-репо (КРИТИЧНО)
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

# IDE / OS junk (обычно меньший risk, но засоряют index)
find "$SYNC_ROOT" -maxdepth 6 \( \
  -name ".idea" -o \
  -name ".vscode" -o \
  -name ".DS_Store" -o \
  -name "Thumbs.db" \
\) 2>/dev/null
```

**Что увидел в результате — то ОБЯЗАТЕЛЬНО исключи в ignore patterns ДО первого sync.**

## Decision Tree: Sync Working Trees vs Git Pull

Для каждой обнаруженной `.git/` папки внутри sync root задай вопрос:

```
Есть ли на ВТОРОЙ ноде live edits / агенты / production runtime в этом репо?
├── ДА → НЕ синкай working tree.
│        Исключи /path/to/repo целиком из sync.
│        Используй `git pull` cron на второй ноде (см. arcanada-pull.sh pattern).
└── НЕТ → working tree можно синкать (read-only сторона)
         Но всё равно исключи .git/ — каждая нода свой commit history.
```

**По умолчанию выбирай ДА** — почти всегда вторая нода рано или поздно станет «активной» (новый агент, deploy script, manual edit). Лучше overprotection.

## Reusable .stignore Template (Syncthing, INFRA-0026 v2)

```gitignore
# === КРИТИЧНО: Project source code (separate git repos) ===
# Каждая нода держит свою checkout-ветку, обновляется через `git pull` независимо.
# НЕ синкается file-sync'ом — иначе working tree конфликты ломают агентов.
/Projects/*/code
/Projects/Datarim/sources
/Projects/Rules of Robotics/Code

# === КРИТИЧНО: AI agents с собственными git/venv ===
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
| `node_modules` | каждая `node_modules/` папка на любом уровне |
| `/Projects/*/code` | path-anchored (`/` префикс) — только конкретный путь |
| `*.db` | каждый `.db` файл на любом уровне |
| `.git/**` | всё внутри `.git` (но не сама папка) |
| `(?d)pattern` | удалить если уже синкнулось (carefuly!) |
| `(?i)pattern` | case-insensitive |
| `!important.log` | negation — НЕ игнорировать (override) |

Source: https://docs.syncthing.net/users/ignoring.html

### rclone (`--exclude` или `.rcignore`)

| Pattern | Matches |
|---|---|
| `node_modules/` | trailing `/` = только папки |
| `**/*.db` | `**` = recurse через папки |
| `/path/to/exclude/**` | path-anchored с / в начале |

### rsync (`--exclude=` или `--exclude-from=file`)

| Pattern | Matches |
|---|---|
| `node_modules` | не разделяет file/dir |
| `/relative/path` | от start dir |
| `**/*.tmp` | recursive glob |

### gitignore (для контекста)

| Pattern | Matches |
|---|---|
| `node_modules` | папка/файл с этим именем на любом уровне |
| `/node_modules` | только в root |
| `**/build` | каждая build папка |

## Workflow для git-managed репо (когда file-sync исключён)

Если ты исключил `/Projects/*/code` из sync, нужен alternate update mechanism для второй ноды:

1. **Cron `git pull` script** — рекомендую `Areas/Infrastructure/scripts/arcanada-pull.sh` pattern:
   - `git fetch` upstream
   - skip if local==remote
   - skip if branch ≠ main/master (агент в feature ветке)
   - stash локальных edits → ff-only pull → fallback merge → fallback CLI Claude conflict resolver → unresolved alert via Ops Bot
   - pop stash → если конфликт, снова Claude

2. **CI/CD self-hosted runner** — GitHub Actions runner на второй ноде делает pull при push в main (event-driven вместо cron polling).

3. **Manual** — пользователь делает `git pull` сам когда нужно. Подходит для редко обновляемых репо.

## Compliance Check (для `/dr-compliance` infrastructure type)

При configuring file-sync обязательно verify:

- [ ] Pre-flight inventory выполнен (`find` для каждого класса)
- [ ] Каждый обнаруженный класс есть в ignore patterns
- [ ] Все вложенные `.git/` директории — либо целиком исключены либо документированы как «read-only mirror»
- [ ] Cross-platform binary классы (`.venv`, `target`, `*.so`/`*.dylib`/`*.dll`) исключены если sync между разными ОС
- [ ] DB файлы (`*.db`, `*.sqlite`) исключены (host-local state)
- [ ] Lockdown настроек применён (`globalAnnounce=false`, no public discovery, transport-only-tailnet)
- [ ] Backup конфигурации сохранён (`config.xml.pre-{TASK-ID}`)
- [ ] Runbook документирован (топология, ops, rollback)
- [ ] Smoke test выполнен (file flow обоими направлениями)

## Related

- `Areas/Architecture/ADR-0001-file-sync-policy.md` — vault-level convention для Arcanada ecosystem
- `Areas/Infrastructure/Syncthing.md` — реальный INFRA-0026 deployment runbook
- `Areas/Infrastructure/scripts/arcanada-pull.sh` — git-pull cron с CLI Claude conflict resolver
- `templates/cli-conflict-resolver-prompt.md` — reusable Claude promp для conflict resolution
