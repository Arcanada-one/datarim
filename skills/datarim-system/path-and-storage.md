# Datarim System — Path and Storage Rules

## File Locations

**CRITICAL:** All Datarim state files reside in `datarim/` at the project root, not in a submodule or nested working directory.

### Path Resolution Rule

Before writing any file to `datarim/`, you MUST resolve the correct path:

1. Check whether `datarim/` exists in the current working directory.
2. If not found, walk up the directory tree until you find a parent containing `datarim/`.
3. If still not found, stop. Do not create the directory unless you are explicitly running `/dr-init`.

**Why:** In monorepos and nested repos, creating `datarim/` in the wrong directory pollutes the subproject and breaks archive/state consistency.

### Quick Shell Check

```bash
DR_DIR=$(pwd); while [ "$DR_DIR" != "/" ]; do [ -d "$DR_DIR/datarim" ] && break; DR_DIR=$(dirname "$DR_DIR"); done
if [ "$DR_DIR" = "/" ]; then print "ERROR: datarim/ not found"; else print "$DR_DIR/datarim"; fi
```

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
- `docs/` — framework evolution log and related documentation

## Documentation Boundary

Completed task archives live outside `datarim/`, in `documentation/archive/{area}/`.

- `datarim/` = local workflow state, normally ignored by git
- `documentation/archive/` = committed long-term project knowledge

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

## Documentation Storage Rules

### Task ID in Report Filenames

All reports must use `{PREFIX}-{NNNN}` in the filename.

Examples:
- `qa-report-TUNE-0002-phase1.md`
- `compliance-report-TUNE-0002-2026-04-15.md`
- `debug-DEV-0053-autosync.md`
- `creative-INFRA-0013-vault-schema.md`

### Prohibited Locations

Never create Markdown files other than `README.md` in:

- application source directories
- component directories such as `frontend/src/` or `backend/src/`
- service root directories except `README.md`
- any directory containing source code
