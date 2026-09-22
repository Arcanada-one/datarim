# Datarim System — Path and Storage Rules

## File Locations

**CRITICAL:** All Datarim state files reside in `datarim/` at the project root, not in a submodule or nested working directory.

### Path Resolution Rule

Before writing task state, resolve an explicitly installed consumer project.
A directory named `datarim/`, including a historical KB, does not enable Datarim.

1. Resolve the physical working directory and find the closest ancestor with
   `.datarim-runtime/installation.json`.
2. Require its recorded `project` to equal that physical ancestor. Copied
   installations and symlinked runtime directories are rejected.
3. Every nested Git repository crossed during this walk must appear in the
   installation's explicit `contexts` list. Otherwise stop at that boundary.
4. Task state is `<resolved-project>/datarim/`. It must already have `tasks.md`
   or `backlog.md`, except when explicitly initializing that project.
5. Never fall back to the user's home, a parent workspace KB, or the framework
   source checkout. A new worktree needs its own explicit installation.
6. **`code/datarim/` is NOT a general convention — never assume it for a
   code-project task.** Only the Datarim framework's own repository ships a
   `code/datarim/` source-tree. For any other project whose code lives under a
   `code/` sub-path, workflow artefacts resolve under that project's own
   installed root (rule 4), not under `code/datarim/`, which does not exist
   there. An agent that pattern-matches "this task's code path contains
   `code/` → look under `code/datarim/`" is applying a framework-specific
   exception where the general rule already applies.
   Precedent: a prior QA incident — `/dr-qa` searched for an expectations file
   under a consumer project's non-existent `code/datarim/` and returned a false
   `BLOCKED "expectations file missing"`; the file was present at the correctly
   resolved path all along. Explicit installation makes the wrong path
   unresolvable rather than merely discouraged, but the pattern-match is what
   produced the false verdict, so the warning is kept.

### Quick Shell Check

```bash
source "${DATARIM_RUNTIME:?}/scripts/lib/resolve-datarim-root.sh"
DR_ROOT=$(resolve_datarim_root "$PWD") || exit 1
printf '%s/datarim\n' "$DR_ROOT"
```

The shell resolver shares `scripts/project_scope.py` with the Jev dispatcher.
`resolve_datarim_root` returns the project root, and `--root` always means that
root rather than the `datarim/` directory itself. Multiple KB directories below
an enabled project produce an advisory; they never change the selected root.

## Negative-Claim Scope Precondition

Any **negative claim** about the knowledge base — "the KB has no X",
"no prior art exists", "zero matches for Y" — MUST be grounded in the
**canonical workspace KB root** (the KB-marked `datarim/` resolved by the
Path Resolution Rule above at the primary workspace), never in a
`datarim/` directory observed **inside a git worktree**.

Why: `datarim/` is gitignored, so a freshly created worktree carries only a
partial skeleton of it — a handful of subdirectories instead of the full
canonical set, with knowledge-bearing directories (insights, research,
creative, design) simply absent. A search inside that skeleton returns zero
matches that *look* like a clean negative result, when in reality the files
were never there to be searched. Acting on such a false negative means
re-doing research the KB already contains, or asserting "no prior art" over
prior art that exists.

**Cheap precondition (run before asserting any negative):** compare the
KB subdirectory count in the current scope against the canonical root's
count:

```bash
ls -d datarim/*/ | wc -l          # current scope
ls -d "<canonical-root>"/datarim/*/ | wc -l   # canonical workspace KB
```

If the current scope's count is **lower**, the scope is a partial skeleton
and is **unfit for negative claims** — re-run the search against the
canonical root before asserting absence. (A positive match found in a
worktree skeleton is still valid; only *negative* conclusions are scope-
sensitive.)

Two companion rules from the same failure class:

- **(a) Search the literal term.** When claiming "X is absent", the search
  MUST have included the literal term `X` (not only synonyms or adjacent
  phrasing). A query about a concept that never greps the concept's own
  name can miss live documents that use it verbatim.
- **(b) Canonical outranks local.** A canonical document carrying
  `status: accepted` outranks a project-local note on the same subject.
  When the two disagree, cite and follow the canonical accepted document;
  flag the local note for reconciliation rather than treating them as
  peers.

## Core Files

- `tasks.md` — active task tracking
- `backlog.md` — active task queue
- `activeContext.md` — current task state
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

## Pinned Project Runtime

The installer copies the reviewed framework into `<project>/.datarim-runtime/`.
Its manifest records the source revision, content digest, project binding, and
managed discovery files. Runtime edits do not modify the framework source.
Propose reusable changes in the source repository through a pull request, then
update each consumer explicitly. Home directories are never an installation target.

The installer exposes native skills in `.agents/skills/`, `.claude/skills/`, and
`.cursor/skills/`. All project instructions live in `AGENTS.md`. Jev key material
lives separately in `config/credentials/jev/api-key`, not in runtime snapshots.

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
