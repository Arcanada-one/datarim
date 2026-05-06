# Getting Started with Datarim

This guide walks you through installing the Datarim framework, initializing it in a project, and running your first task.

---

## Prerequisites

- [Claude Code](https://code.claude.com/docs/en/overview) CLI installed and authenticated. Install: `curl -fsSL https://claude.ai/install.sh | bash` (macOS/Linux/WSL) or `irm https://claude.ai/install.ps1 | iex` (Windows PowerShell)
- A git repository for your project (Datarim uses `.gitignore` to separate workflow state from project documentation)
- **Recommended:** [context7](https://github.com/upstash/context7) MCP server for token-efficient documentation access when looking up library docs

---

## Installation

### Quick start (symlink mode — default since v1.17.0)

```bash
git clone https://github.com/Arcanada-one/datarim.git
cd datarim
chmod +x install.sh
./install.sh
```

On macOS and Linux this creates four symlinks in `~/.claude/` — `agents`, `skills`, `commands`, `templates` — each pointing at the matching directory inside the cloned repo. The runtime IS the repo: any edit you make in either place lands in the same file, so `git diff` shows your changes immediately and there is no separate "curate" step.

The installer also creates `~/.claude/local/{skills,agents,commands,templates}/` (real directories, gitignored) for personal additions and overrides that you do not want committed upstream. See [Local Overlay](#local-overlay) below.

### Copy mode (legacy / Windows)

If symlinks are not available — typical on Windows Git Bash, FAT32/exFAT volumes, or restricted shells — pass `--copy` (or let the installer auto-detect):

```bash
./install.sh --copy             # explicit copy mode
./install.sh --copy --force --yes   # CI / scripted overwrite (creates backup)
```

`uname -s` matching `MINGW*`, `MSYS*`, or `CYGWIN*` triggers the copy fallback automatically; the installer prints `Mode: copy (auto-detected: symlinks not available)`.

### Migration from v1.16 (existing copy install)

The first time `./install.sh` is run against a v1.16 copy install, it shows an interactive prompt:

```
Options:
  [c] Convert to symlinks (recommended)
       Existing files moved to $CLAUDE_DIR/backups/migrate-<ts>/
       Future updates run via 'git pull' inside the repo — no copy step.
  [k] Keep copy mode permanently
       Re-run install.sh --copy from now on.
  [a] Abort
```

`--yes` (or `DATARIM_INSTALL_YES=1`) auto-selects `[c]`. CI / non-TTY environments without auto-consent abort with exit 1 — pick `--copy` or `--yes` explicitly.

### Local overlay

`~/.claude/local/` is the user-private layer:

```
~/.claude/local/
├── skills/        # personal skills, e.g. my-company-style.md
├── agents/
├── commands/
├── templates/
├── .gitignore     # contents `*` — entire dir is private
└── README.md      # convention notes
```

Loader order (`skills/datarim-system.md` § Loading Order): the framework layer loads first, then files in `local/<scope>/<name>.md` override framework files of the same name. `validate.sh` emits a `WARN: override detected: …` line per shadow.

**Critical-skill blocklist.** Six skills cannot be shadowed from `local/skills/`:
`security.md`, `security-baseline.md`, `compliance.md`, `datarim-system.md`,
`ai-quality.md`, `evolution.md`. They define the security contract and core
workflow invariants — silently overriding them via overlay would let a personal
file relax rules that downstream agents and CI gates rely on. Placing any of
these names in `local/skills/` makes `validate.sh` exit **1** with an `ERROR:
critical skill ...` line. Customise by forking or upstream PR. The blocklist is
path-scoped to the `skills/` directory; same basename under `local/agents/`,
`local/commands/`, or `local/templates/` is allowed (standard WARN).

**Convention:** prefix overlay files with a personal namespace (`my-org-…`, your initials, …) so you don't accidentally shadow framework files you actually want to track upstream.

### Manual install (no script)

```bash
mkdir -p ~/.claude
ln -s "$(pwd)/agents"    ~/.claude/agents
ln -s "$(pwd)/skills"    ~/.claude/skills
ln -s "$(pwd)/commands"  ~/.claude/commands
ln -s "$(pwd)/templates" ~/.claude/templates
mkdir -p ~/.claude/local/{skills,agents,commands,templates}
```

Or, for copy mode (the legacy v1.16 path):

```bash
mkdir -p ~/.claude/{agents,skills,commands,templates}
cp agents/*.md ~/.claude/agents/
cp skills/*.md ~/.claude/skills/
cp commands/*.md ~/.claude/commands/
cp templates/*.md ~/.claude/templates/
cp templates/*.sh ~/.claude/templates/ 2>/dev/null || true
chmod +x ~/.claude/templates/*.sh 2>/dev/null || true
```

### Fork-as-contributor (advanced)

If you intend to upstream framework changes back to `Arcanada-one/datarim`, fork the repo on GitHub, clone your fork, and clone-and-symlink against it. For *personal additions* prefer the `local/` overlay — fork merge conflicts on Markdown are a real UX barrier (this is why oh-my-zsh / bash-it / chezmoi all use overlays for end-user additions).

### Installer Contract

The installer has a deliberately narrow contract — review a diff of `install.sh` if you want the authoritative version.

**Install scopes** (linked or copied into `$CLAUDE_DIR`, default `~/.claude/`):

| Scope | Content types | Notes |
|-------|---------------|-------|
| `agents/`    | `.md` | Agent personas |
| `skills/`    | `.md` | Skills, including supporting subdirectories (`datarim-system/`, `visual-maps/`) |
| `commands/`  | `.md` | Slash-command definitions |
| `templates/` | `.md`, `.sh`, `.json`, `.yaml`, `.yml` | Reusable scaffolds. `.sh` templates get `+x` automatically in copy mode (symlink mode preserves the source bits). |

**Repo-only** (intentionally NOT installed):

- `scripts/` — dev tooling (`check-drift.sh`, `pre-archive-check.sh`, `curate-runtime.sh` — both `check-drift` and `curate-runtime` are deprecated since v1.17 and will be removed in v1.18, TUNE-0044). These run from the cloned repo.
- `tests/` — bats tests for the repo's own scripts.
- `install.sh`, `update.sh`, `validate.sh`, `VERSION`, `CLAUDE.md`, `README.md`, `LICENSE` — repo artefacts.

**Content-type whitelist.** In copy mode, files with extensions outside the whitelist are logged (`WARN (unknown extension, skipped)`) and not copied. In symlink mode the entire scope dir is exposed wholesale, so the whitelist does not apply at install time.

**`--force` safety:**

- Symlink topology + `--force` → no-op (prints "Already symlinked, nothing to update"). Use `cd repo && git pull` or `./update.sh` instead.
- Copy topology + `--force` (TUNE-0004 hardening): `CLAUDE_DIR` sanity-checked, live-system consent required (`yes` typed at TTY, or `--yes` / `DATARIM_INSTALL_YES=1`), backup of each scope under `$CLAUDE_DIR/backups/force-<UTC-timestamp>/` with a `SUCCESS` marker written last.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Success (or symlink-mode no-op) |
| `1` | Migration aborted, `--force` declined, or non-TTY without `--yes` |
| `2` | Invalid arguments, or `CLAUDE_DIR` sanity guard tripped |

**Drift between repo and runtime.** Under symlink mode, drift is impossible by definition — runtime IS the repo. `./scripts/check-drift.sh` exits 0 in that case (and is itself deprecated since v1.17, planned for removal in v1.18 along with `curate-runtime.sh`). Under copy mode, the script behaves as before.

---

## Updating Datarim

If you have Datarim installed and want to get the latest version:

```bash
cd /path/to/datarim              # your cloned repo
./update.sh                      # pull + verify — one command
```

`update.sh` branches on the runtime topology it detects:

- **Symlink mode (default):** runs `git pull origin main` and exits. The runtime is the repo, so the pull IS the install.
- **Copy mode:** `git pull origin main` then `./install.sh --copy --force --yes` then `./scripts/check-drift.sh --quiet`.

Use `./update.sh --dry-run` to preview what would change without writing anything.

### Manual alternative

Symlink mode:

```bash
cd /path/to/datarim
git pull origin main
```

Copy mode:

```bash
git pull origin main
./install.sh --copy --force      # overwrites all (backup taken on live system)
./scripts/check-drift.sh         # verify sync (deprecated, removal v1.18)
```

### What stays unchanged

- Your project `CLAUDE.md` files — they live in your project, not in `~/.claude/`
- Your `datarim/` workflow state — local to each project
- Your `documentation/archive/` — committed to your project's git
- Your `~/.claude/local/` overlay — never touched by `install.sh` after the initial directory + `.gitignore` scaffold

---

### Activate in Your Project

After installation, copy `CLAUDE.md` into your project root:

```bash
cp /path/to/datarim/CLAUDE.md /path/to/your/project/
```

This file contains the framework rules that Claude Code reads on startup. The top section defines the pipeline, agents, and skills. The bottom section is where you describe your project, tech stack, and conventions. Customize the bottom section freely; leave the top section as-is.

---

## Initializing Datarim in a Project

Navigate to your project root and start Claude Code:

```bash
cd your-project
claude
```

Then run:

```
/dr-init "Your task description"
```

If `datarim/` does not exist yet, `/dr-init` creates it along with the documentation directory structure. After initialization, your project looks like this:

```
your-project/
├── CLAUDE.md               # Framework rules (COMMITTED)
├── .gitignore              # datarim/ added here
├── datarim/                # Workflow state (LOCAL, not committed)
│   ├── activeContext.md    # Current task state
│   ├── tasks.md            # Active task tracking
│   ├── backlog.md          # Pending tasks queue
│   ├── backlog-archive.md  # Completed/cancelled task history
│   ├── progress.md         # Overall progress
│   ├── projectbrief.md     # Project overview
│   ├── productContext.md   # Product requirements
│   ├── systemPatterns.md   # Architecture patterns
│   ├── techContext.md      # Technology context
│   ├── style-guide.md      # Code style guide
│   ├── prd/                # Product Requirements Documents
│   ├── tasks/              # Task documentation
│   ├── creative/           # Design phase documents
│   ├── reflection/         # Reflection documents
│   ├── qa/                 # QA reports
│   ├── reports/            # Diagnostic reports
│   └── docs/               # Evolution log
└── documentation/          # Project documentation (COMMITTED)
    └── archive/            # Completed task archives
        ├── infrastructure/
        ├── web/
        ├── development/
        └── ...
```

---

## Two-Layer Architecture

Datarim separates workflow state from project documentation. This is the central design decision behind the directory structure.

### `datarim/` -- Local Workflow State

This directory contains everything related to the *process* of working on tasks: the active task, backlog, context files, PRDs, reflections, QA reports, and design documents.

- Added to `.gitignore` -- stays on each developer's local machine
- Not relevant to the project's applications or build process
- Each developer maintains their own independent `datarim/` directory
- Can be deleted and recreated at any time without affecting the project

### `documentation/archive/` -- Project Documentation

This directory contains the *results* of completed tasks: what was decided, why, and how it was implemented.

- Committed to git -- becomes the project's knowledge base
- Organized by topic area (infrastructure, web, content, research, etc.)
- Shared across the team -- everyone sees the same archive
- Grows over time into a searchable record of project decisions

### Why This Separation?

The process of working on tasks -- planning, reflecting, running QA -- is personal workflow. It does not belong in git history. Different developers may work on different tasks simultaneously, and their workflow files would conflict.

But the *result* of completed tasks -- what was decided, why, and how it was implemented -- is valuable project documentation. When a new team member joins, they read `documentation/archive/` to understand the project's history. When someone asks "why did we choose PostgreSQL over MongoDB?", the answer is in the archive.

This gives you:

- **No merge conflicts** on workflow files -- each developer has their own `datarim/`
- **Clean git history** -- no ephemeral files (drafts, QA reports, intermediate context) cluttering commits
- **Shared knowledge** -- completed task archives are available to everyone through git
- **Project managers can track progress** by reading `documentation/archive/` without using Claude Code

---

## The .gitignore Pattern

When `/dr-init` runs for the first time, it adds `datarim/` to your `.gitignore`:

```gitignore
# Datarim workflow state (local only)
datarim/
```

**Do NOT gitignore** `documentation/` -- that directory holds your project's knowledge base and should be committed.

If your project does not have a `.gitignore` file, `/dr-init` will offer to create one.

---

## Archive Organization

When a task is completed and archived with `/dr-archive`, the archive file goes to `documentation/archive/{area}/` based on the task ID prefix:

| Prefix | Area | Examples |
|--------|------|---------|
| `INFRA-*` | `infrastructure/` | Server setup, DNS, SSL, deploy pipelines |
| `WEB-*` | `web/` | Websites, landing pages, frontend work |
| `DEV-*` | `development/` | Code features, APIs, libraries |
| `CONTENT-*` | `content/` | Articles, blog posts, marketing materials |
| `RESEARCH-*` | `research/` | Analysis, investigations, literature reviews |
| `AGENT-*` | `agents/` | AI agents, bots, automation |
| `DEVOPS-*` | `devops/` | CI/CD, pipelines, automation infrastructure |
| `BENCH-*` | `benchmarks/` | Performance benchmarks, comparisons |
| `TUNE-*` | `framework/` | Framework improvements, tuning |
| `ROB-*` | `framework/` | Rules of Robotics, governance |
| `MAINT-*` | `maintenance/` | Cleanup, maintenance, housekeeping |
| `FIN-*` | `finance/` | Financial tasks, budgets, reports |
| `QA-*` | `qa/` | Quality assurance, testing initiatives |
| *(unknown)* | `general/` | Anything that does not match a known prefix |

The archive file is named `archive-{task_id}.md` (for example, `documentation/archive/web/archive-WEB-0042.md`).

The full mapping is defined in the `datarim-system.md` skill.

---

## Team Workflow

In a team setting, Datarim supports parallel work without conflicts:

1. **Each developer runs `/dr-init`** to set up their local `datarim/` directory. This happens once per project, per developer.

2. **Developers work independently.** Each developer has their own tasks, backlog, active context, and reflections. There is no shared workflow state to conflict on.

3. **When a task is completed**, `/dr-archive` writes the archive to `documentation/archive/` (shared via git). The developer commits and pushes the archive file.

4. **Project managers read `documentation/archive/`** for progress and decisions. They do not need Claude Code -- the archives are plain Markdown files readable in any editor, IDE, or Git web interface.

5. **Cross-team task coordination** happens through the backlog. Developers can manually add items to each other's `backlog.md`, or maintain a shared backlog file outside `datarim/`.

---

## Your First Task

After initialization, the pipeline depends on the task's complexity level. Datarim assesses this automatically.

### L1 -- Quick Fix (single file, < 50 lines)

```
/dr-init "Fix the typo in the README header"
/dr-do
/dr-archive
```

### L2 -- Enhancement (2-5 files, < 200 lines)

```
/dr-init "Add input validation to the login form"
/dr-plan
/dr-do
/dr-archive
```

### L3+ -- Feature or Major (5+ files, 200+ lines)

```
/dr-init "Implement OAuth2 authentication"
/dr-prd
/dr-plan
/dr-design
/dr-do
/dr-qa
/dr-archive
```

> **Note:** reflection runs automatically inside `/dr-archive` as mandatory Step 0.5 (v1.10.0, TUNE-0013). You do not invoke it separately.

You do not need to memorize these routes. After each stage, Datarim tells you what comes next. Run `/dr-status` at any time to see where you are in the pipeline.

If you take a break and come back later, `/dr-continue` reads your `activeContext.md` and picks up where you left off.

---

## Post-Setup Checklist

After running `/dr-init` for the first time, verify:

- [ ] `datarim/` directory exists at your project root
- [ ] `documentation/archive/` directory exists at your project root
- [ ] `datarim/` is listed in `.gitignore`
- [ ] `datarim/tasks.md` exists and contains your task
- [ ] `datarim/activeContext.md` exists and shows the current task
- [ ] `datarim/backlog.md` exists
- [ ] `CLAUDE.md` exists at your project root with the project-specific section filled in

---

## Framework Maintenance Commands

Three commands help you keep the framework itself healthy over time:

| Command | Purpose |
|---------|---------|
| `/dr-doctor` | Diagnose and repair Datarim operational files — migrate to thin one-liner schema, externalize task descriptions, abolish progress.md. Run when upgrading from older Datarim versions. |
| `/dr-optimize` | Audit framework health: prune unused components, merge duplicates, fix broken references, sync documentation. Suggests actions but does not auto-apply without confirmation. |
| `/dr-dream` | Knowledge base maintenance: organize files, build cross-reference index, flag contradictions, archive stale content. Run periodically as the knowledge base grows. |

Run `/dr-doctor` if you are upgrading from a pre-v1.19.0 installation or if `/dr-status` reports structural anomalies.

---

## Next Steps

- [Pipeline Stages](pipeline.md) -- detailed reference for each of the 9 pipeline stages
- [Commands Reference](commands.md) -- all 20 available commands with usage examples
- [Backlog Workflow](backlog-workflow.md) -- how to manage tasks, priorities, and the backlog
- [Complexity Routing](complexity.md) -- how task complexity determines which stages run

## Adding plugins (v1.23.0+)

Datarim ships with a built-in `datarim-core` set. Optional skills, agents, commands, and templates beyond core are managed via the `/dr-plugin` CLI (TUNE-0101).

```bash
/dr-plugin list                              # active set + bootstrap on first run
/dr-plugin enable /path/to/my-plugin         # absolute path to a directory with plugin.yaml
/dr-plugin disable my-plugin
/dr-plugin sync                              # reconcile runtime ↔ manifest (idempotent)
/dr-plugin doctor [--fix]                    # 9 health checks
```

Each plugin source is a directory containing `plugin.yaml` (schema_version: 1) and one or more of the `skills/`, `agents/`, `commands/`, `templates/` subdirectories. Files install as symlinks under `~/.claude/<category>/<plugin-id>/<basename>` (namespace-isolated). Root-position install is opt-in via the `overrides:` field in `plugin.yaml` — useful when a plugin intentionally shadows a core artefact via the `local`-overlay precedence.

The active set is recorded in `datarim/enabled-plugins.md` — manual edits are tolerated but require a follow-up `/dr-plugin sync` to reconcile runtime symlinks. Every `enable` takes a tarball snapshot before applying changes; on mid-apply failure the snapshot restores atomically.

**Health checks** (`/dr-plugin doctor`): manifest-syntax, inventory-consistency, broken-symlinks, orphan-files, override-integrity, dependency-graph (DFS cycle/dangling), git-state, snapshot-cleanup (>30d), skill-registry (frontmatter `name:` ↔ basename). Exit codes: `0` clean, `1` warnings only, `2` errors found, `64` usage error.

For full reference see `commands/dr-plugin.md` and `templates/plugin.yaml.template`.

