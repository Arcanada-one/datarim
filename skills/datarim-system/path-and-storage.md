# Datarim System — Path and Storage Rules

## File Locations

**CRITICAL:** All Datarim state files reside in `datarim/` at the project root, not in a submodule or nested working directory.

### Path Resolution Rule

Before writing any file to `datarim/`, you MUST resolve the correct path. The contract is **«one KB per git repository»** — the canonical `datarim/` lives at the git-root of the current repository and is identifiable by KB markers (`tasks.md`, `backlog.md`).

1. If `pwd` is inside a git repository, prefer `<toplevel>/datarim/` when it both (a) exists and (b) carries at least one KB marker (`tasks.md` OR `backlog.md`). This is the **canonical anchor** — it returns the KB of the current repo regardless of nested or sibling `datarim/` directories.
2. Otherwise (outside git, or the git-root has no KB-marked `datarim/`), walk up the directory tree from `pwd` and use the **first** parent containing a KB-marked `datarim/` (must have `tasks.md` or `backlog.md`). A plain `datarim/` directory without markers is **not** a KB — most commonly this is the framework source-tree (`code/datarim/skills/...`), which must not be mistaken for a KB.
3. If still not found, stop. Do not create the directory unless you are explicitly running `/dr-init`.
4. If more than one KB-marked `datarim/` is found in the parent chain **above** the resolved one (without each having its own `.git/` boundary), emit a `WARN:` line to stderr listing both paths — this signals a misplaced KB and should be reported to the operator.

**Why:** In monorepos and nested workspaces with multiple projects under one `.git/`, the historical walk-upward («first match wins») resolved to whichever `datarim/` happened to be closest to `pwd` — that picked up rogue/per-project `datarim/` directories instead of the canonical root one, fragmenting the KB. Anchoring to the git toplevel restores «one KB per git repo» and makes the resolver deterministic regardless of CWD inside the tree. Sub-projects with their own `.git/` (sub-repo / sibling clone) retain their own canonical `datarim/` — the git-root anchor naturally respects that boundary. The KB-marker check (`tasks.md` / `backlog.md` presence) disambiguates an actual KB from a same-named source-tree directory (e.g. `code/datarim/` contains the framework's `skills/agents/commands/templates/` source, not workflow state).

### Quick Shell Check

```bash
_dr_is_kb() {
    # A real KB carries at least one of the canonical operational files.
    [ -d "$1" ] && { [ -f "$1/tasks.md" ] || [ -f "$1/backlog.md" ]; }
}

DR_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
DR_DIR=""
if [ -n "$DR_ROOT" ] && _dr_is_kb "$DR_ROOT/datarim"; then
    DR_DIR="$DR_ROOT"
else
    CUR=$(pwd)
    while [ "$CUR" != "/" ]; do
        if _dr_is_kb "$CUR/datarim"; then
            DR_DIR="$CUR"
            break
        fi
        CUR=$(dirname "$CUR")
    done
fi

if [ -z "$DR_DIR" ]; then
    printf 'ERROR: datarim/ not found (no directory with tasks.md or backlog.md)\n' >&2
    exit 1
fi

# advisory: warn if more than one KB-marked datarim/ is visible below the chosen anchor
EXTRA=$(find "$DR_DIR" -mindepth 2 -maxdepth 5 -type d -name datarim \
    -not -path '*/.git/*' 2>/dev/null \
    | while read -r d; do _dr_is_kb "$d" && printf '%s\n' "$d"; done | head -n 5)
if [ -n "$EXTRA" ]; then
    printf 'WARN: multiple KB-marked datarim/ visible — using %s/datarim; also seen:\n%s\n' \
        "$DR_DIR" "$EXTRA" >&2
fi

printf '%s/datarim\n' "$DR_DIR"
```

This rule is implemented once, canonically, in `scripts/lib/resolve-datarim-root.sh` — `resolve_datarim_root [start]` echoes the **repo-root** (the parent of the KB-marked `datarim/`), and `assert_not_nested_datarim <root>` rejects a root already inside a `datarim/` (the `datarim/datarim/` nesting vector). Every consumer that needs the KB location (the snapshot writer, `datarim-doctor.sh`, the `dev-tools/check-*.sh` validators) sources this file rather than re-implementing the walk-up — three divergent re-implementations were the root cause of nested directories and a missed `docs→history` migration. The `--root` argument means **repo-root** everywhere.

## Core Files

- `tasks.md` — active task tracking
- `backlog.md` — active task queue
- `backlog-archive.md` — historical backlog items
- `activeContext.md` — current task state
- `progress.md` — overall progress
- `projectbrief.md` — project overview
- `productContext.md` — product requirements
- `systemPatterns.md` — system patterns
- `techContext.md` — technical context
- `style-guide.md` — code style guide

## Core Directories

- `prd/` — PRDs
- `tasks/` — operational task documentation
- `creative/` — creative/design docs
- `reflection/` — reflection documents
- `qa/` — QA reports
- `reports/` — debug, diagnostic, and compliance reports
- `history/` — append-only KB ledgers (evolution-log, activity-log, patterns); committed via `.gitignore` negation
- `insights/` — research insights documents (created by /dr-prd Phase 1.3, updated by /dr-do gap discovery)

## Documentation Boundary

Completed task archives live outside `datarim/`, in `documentation/archive/{area}/`.

- `datarim/` = local workflow state, normally ignored by git
- `datarim/history/` = committed append-only KB ledgers (the exception inside the otherwise-ignored `datarim/`)
- `documentation/archive/` = committed long-term project knowledge

`datarim/history/` holds the append-only ledgers (`evolution-log.md`, `activity-log.md`, `patterns.md`) that the framework writes across tasks. They are knowledge-base content, so they are **committed** even though the rest of `datarim/` is gitignored. Because the consumer `.gitignore` ignores `/datarim/` wholesale, git never descends into it — so a bare `!/datarim/history/` does NOT un-ignore the contents. The negation MUST re-include the directory **and** its contents:

```gitignore
/datarim/
!/datarim/history/
!/datarim/history/**
```

`datarim-doctor.sh --fix` migrates a legacy `datarim/docs/` ledger directory to `datarim/history/`, relocates any `ADR-*.md` to `documentation/architecture/`, and writes this negation block automatically.

```text
documentation/
└── archive/
    ├── infrastructure/
    ├── web/
    ├── content/
    ├── research/
    ├── agents/
    ├── benchmarks/
    ├── development/
    ├── devops/
    ├── framework/
    ├── maintenance/
    ├── finance/
    ├── qa/
    ├── optimized/
    └── general/
```

## Symlink Architecture

The framework runtime directories in `$HOME/.claude/` are **symlinks** pointing to the Datarim git repository. This means edits to skills/commands/agents/templates in runtime are automatically tracked by git.

| Runtime path | Symlink target |
|-------------|---------------|
| `$HOME/.claude/skills/` | `Projects/Datarim/code/datarim/skills/` |
| `$HOME/.claude/commands/` | `Projects/Datarim/code/datarim/commands/` |
| `$HOME/.claude/agents/` | `Projects/Datarim/code/datarim/agents/` |
| `${DATARIM_RUNTIME:-$HOME/.claude}/templates/` | `Projects/Datarim/code/datarim/templates/` |

**Implications:**
- `git diff` in the Datarim repo shows runtime changes to skills/commands/agents/templates
- No manual sync needed for these 4 directories — symlinks keep them identical
- `install.sh` is needed only for first-time setup or rollback from backup
- Backup of pre-symlink originals: `$HOME/.claude/backups/pre-symlink-2026-04-22/`
- If the repo path changes, symlinks must be recreated

**Established:** 2026-04-22.

## Documentation Storage Rules

### Task ID in Report Filenames

All reports must use `{PREFIX}-{NNNN}` in the filename.

Examples:
<!-- gate:history-allowed -->
- `qa-report-TUNE-0002-phase1.md`
- `compliance-report-TUNE-0002-2026-04-15.md`
- `debug-DEV-0053-autosync.md`
- `creative-INFRA-0013-vault-schema.md`
<!-- /gate:history-allowed -->

### Prohibited Locations

Never create Markdown files other than `README.md` in:

- application source directories
- component directories such as `frontend/src/` or `backend/src/`
- service root directories except `README.md`
- any directory containing source code
