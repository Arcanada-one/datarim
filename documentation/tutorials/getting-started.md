# Getting Started with Datarim

Datarim is a workflow framework for AI coding agents. It installs **into one
project at a time** and runs only when you call one of its `/dr-*` commands.
It adds nothing to your agents' instructions otherwise, and nothing it writes
appears in `git status`.

## Prerequisites

- **Python 3.10+** and **git**.
- At least one agent client: [Claude Code](https://code.claude.com/docs/en/overview),
  [Codex CLI](https://github.com/openai/codex), or Cursor.
- A project directory — ideally a git repository.

## Install into a project

```bash
# nosec-extract
git clone https://github.com/Arcanada-one/datarim.git
cd datarim
./install.sh --project /path/to/project --init --dry-run   # preview what it would write
./install.sh --project /path/to/project --init             # install
```

Add `--with-jev` to install Jev alongside (routing advice and a safety floor;
see [Initialize Datarim with Jev](initialize-datarim-with-jev.md)), or
`--with-jev --host-jev` to reuse a Jev you already installed for the whole
machine. `--expose-skills` additionally puts every framework skill into your
clients' automatic discovery — their descriptions are then loaded into every
session, so leave it off unless you want that.

### What the install writes

| Where | What | Visible in git |
|---|---|---|
| `.datarim-runtime/` | the framework at this revision | no |
| `.claude/commands/dr-*.md` | the commands for Claude Code | no |
| `.agents/skills/dr-*/`, `.cursor/skills/dr-*/` | the same commands for Codex and Cursor | no |
| `datarim/` (with `--init`) | this project's task state | no |
| `.git/info/exclude` | the rules that keep all of the above out of `git status` | never committed |

It does **not** touch `AGENTS.md`, `CLAUDE.md`, `.gitignore` or your home
directory. Each command carries the path to `.datarim-runtime/` and tells the
agent to read the framework rules from there — so the framework is loaded when
you run a command, and not otherwise. In a repository shared with people who do
not use Datarim, they see nothing.

If the project is not a git repository there is nothing to hide, and no
exclude file is written.

### Check it

```bash
cd /path/to/project
git status --short                     # nothing from Datarim
source .datarim-runtime/activate.sh    # current shell only
jev doctor
```

Then, in Claude Code, run `/dr-help`. In Codex and Cursor the commands arrive
as skills named `dr-*`: ask the agent to run the `dr-help` skill.

### Upgrading from 2.x

Datarim 2.x installed globally (`./install.sh --with-claude`, symlinks into
`~/.claude/`). Those flags no longer exist. Remove the old symlinks in
`~/.claude/{agents,skills,commands,templates,scripts,tests,dev-tools}` (and the
Codex and Cursor equivalents) that resolve into your Datarim checkout — only
those — and install per project as above.

A project installed from `main` before 3.0 had a block appended to its
`AGENTS.md` and rules appended to `.gitignore`. The next install or update
removes both, keeps everything else in those files, and stops managing them.

## Updating

```bash
cd /path/to/datarim && git pull
./install.sh --project /path/to/project
```

The update is a single transaction: it verifies every file it will change,
refuses to overwrite anything you edited, and rolls back on failure.

## Removing

```bash
./install.sh --project /path/to/project --uninstall
```

The runtime moves to `.datarim-uninstalled/`; keys and task state stay, and stay
hidden from git.

---

## Initializing Datarim in a Project

Navigate to your project root and start your agent:

```bash
# nosec-extract
cd your-project
claude
```

Then run:

```
/dr-init "Your task description"
```

During Step 2.5b (added in v2.7.0) `/dr-init` runs a non-blocking topic-overlap advisory: if your description shares ≥2 keyword stems with a **pending** backlog item, the matching IDs are printed so you can catch potential duplicates before committing to a fresh task. The check is silent when no overlap is found, when `backlog.md` carries no pending items, or when `python3` is unavailable. RU + EN input both work — tokenisation is language-aware.

During Step 4.7 (added in v2.17.1) `/dr-init` writes a mandatory expectations skeleton to `datarim/tasks/{TASK-ID}-expectations.md`. The skeleton extracts your operator goals into individual wishes (L1 — 1 wish; L2-L4 — 2-5 wishes), each carrying an explicit `evidence_type: empirical | static | measurement`. The downstream `/dr-qa` Layer 3b verifies each wish individually and writes a per-wish detailed report block. The mandate applies to all complexity levels (no soft window); legacy tasks (`legacy: true` or pre-pivot captured_at) are exempt. For deploy-class tasks (those touching systemd units, sudoers, CI cutover jobs, or `.env-deploy` templates), `/dr-qa` also runs Layer 4g (Prod-Readiness Gate): a read-only test↔prod runner symmetry probe that blocks the merge recommendation until production is verified, and `/dr-archive` Step 0.4 blocks archiving until the production merge is done and verified (added in v2.30.0).

If `datarim/` does not exist yet, `/dr-init` creates it along with the documentation directory structure. After initialization, your project looks like this:

```
your-project/
├── .datarim-runtime/       # The framework (local, hidden from git)
├── datarim/                # Workflow state (local, hidden from git)
│   ├── activeContext.md    # Current task state
│   ├── tasks.md            # Active task tracking
│   ├── backlog.md          # Pending tasks queue
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
│   └── history/            # Committed KB ledgers (evolution-log, activity-log, patterns)
└── documentation/          # Project documentation (COMMITTED)
    └── archive/            # Completed task archives
        ├── infrastructure/
        ├── web/
        ├── development/
        └── ...
```

---

---

## Project Scaffolding — Diátaxis Documentation Structure

When `/dr-init` is invoked with a project-creation intent (e.g. `/dr-init create project "Foo"`), the scaffolder follows the **Documentation Taxonomy Mandate** (`skills/diataxis-docs/SKILL.md`). The default `documentation/` layout is the four Diátaxis categories with auto-mapped legacy stubs:

```
your-project/documentation/
├── tutorials/              # Learning-oriented (newcomer end-to-end)
│   └── README.md
├── how-to/                 # Problem-solving (task recipes)
│   ├── README.md
│   ├── testing.md          # Legacy stub mapped to how-to
│   ├── deployment.md       # Legacy stub mapped to how-to
│   └── gotchas.md          # Legacy stub mapped to how-to
├── reference/              # Information-oriented (lookup, catalogue)
│   ├── README.md
│   └── architecture.md     # Legacy stub mapped to reference (system map)
└── explanation/            # Understanding-oriented (background, why)
    └── README.md
```

The four categories are a **closed set** — `faq`, `glossary`, `troubleshooting`, `examples`, `overview`, `samples` are mappable to one of the four canonical buckets, never separate top-level types. See `skills/diataxis-docs/SKILL.md` § Mapping Table for the full mapping (architecture / testing / deployment / gotchas / api / cli / config / concepts / design / tutorial / quickstart / faq / troubleshooting / examples / glossary).

**Idempotency:** `/dr-init` never overwrites existing files. If `documentation/` already exists with files, the scaffolder skips them and reports "skipped: already exists" per file.

**Stack-agnostic:** the mandate describes taxonomy only — your choice of static-site generator (any) is per-project and outside the contract.

**Drift detection:** `/dr-optimize` Step 6 detects repos with ≥3 `documentation/*.md` files but missing the 4-category split, and proposes `INFRA-* — Diátaxis docs reorg` in backlog. Soft warning only at this stage; a future hard CI gate is deferred to a separate backlog item.

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

## Keeping workflow state out of git

`datarim/` is local. The installer hides it through the clone-local
`.git/info/exclude`, and `/dr-init` checks that with `git check-ignore` —
neither edits your `.gitignore`, which the project may share with people who do
not run Datarim.

**Do not hide** `documentation/` — that directory holds your project's
knowledge base and should be committed.

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

The archive file is named `archive-{task_id}.md` (for example, `documentation/archive/web/archive-<TASK-ID>.md`).

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

During `/dr-plan`, Datarim checks the whole task scope before detailed planning.
If every deliverable only removes redundancy, dead code, or duplicate surfaces
without adding behavior—or if that claim is still ambiguous—the strategist
review is mandatory even for L1/L2. Datarim logs one scope-bound decision; L3/L4
reuse their normal strategist invocation. A valid `GO` reaches the existing
architectural-superseding probe, not implementation, and every later hard gate
still applies. Clearly non-matching work follows the normal complexity route.

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

> **Note:** reflection runs automatically inside `/dr-archive` as mandatory Step 0.5 since v1.10.0. You do not invoke it separately.

You do not need to memorize these routes. After each stage, Datarim tells you what comes next. Run `/dr-status` at any time to see where you are in the pipeline.

If you take a break and come back later, `/dr-next` reads your `activeContext.md` and picks up where you left off.

---

## Post-Setup Checklist

After running `/dr-init` for the first time, verify:

- [ ] `datarim/` directory exists at your project root
- [ ] `documentation/archive/` directory exists at your project root
- [ ] `git status` shows nothing under `datarim/` or `.datarim-runtime/`
- [ ] `datarim/tasks.md` exists and contains your task
- [ ] `datarim/activeContext.md` exists and shows the current task
- [ ] `datarim/backlog.md` exists

---

## Context Management (v2.13.0+)

Every `/dr-*` command persists its final operator-visible response (Summary + Gate Results + CTA) to `datarim/snapshots/{TASK-ID}.snapshot.md` with overwrite semantics. After `/clear` or a closed terminal, `/dr-next {TASK-ID}` (and `/dr-orchestrate` resume) reads this snapshot FIRST — before task-description, init-task, activeContext — and emits a replay-prompt with the recommended CTA plus a bilingual autonomy reminder. If no snapshot exists, both commands fall through to legacy behaviour without warning lines.

- Storage: `datarim/snapshots/` (gitignored; archived snapshot lands in `documentation/archive/<subdir>/snapshots/{TASK-ID}-final-stage.md` at `/dr-archive`).
- Kill-switch: `export DATARIM_DISABLE_SNAPSHOT=1` makes the writer no-op.
- How-to with full reference: [`documentation/how-to/stage-snapshots.md`](../how-to/stage-snapshots.md).

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

## Autonomous Mode (`/dr-auto`)

Когда операторские уточнения дороже агентского исследования — `/dr-auto` активирует **autonomous mode** на стадии одного цикла. Команда не вводит новых правил: она активирует существующий `documentation/mandates/autonomous-agents.md` (FB-1..8) + L1 Inline Resolution Rule + autonomous-ops scope как **default-on**, пока маркер `datarim/.auto-mode-active` существует.

### Two modes

- **Continue** — `/dr-auto {TASK-ID}` поднимает task через snapshot-first read (как `/dr-next`) и продолжает её до полного закрытия или hard-gated stop.
- **Bootstrap** — `/dr-auto "<free-text description>"` запускает full pipeline `/dr-init → /dr-prd? → /dr-plan → /dr-do → /dr-qa → /dr-compliance → /dr-archive` с активным question-suppression.

### Question Suppression Ladder

Перед каждым `AskUserQuestion` агент проходит 5 уровней (останавливается на первом, который даёт unambiguous answer):

| L | Источник | Когда применимо |
|---|----------|-----------------|
| 1 | Codebase grep / file read | Технический вопрос про код, конфиг, версии |
| 2 | Runtime probe (curl, docker, git, gh, vault) | Состояние сервиса, БД, CI, secrets-схема |
| 3 | MEMORY.md feedback lookup | Operator preferences, prior decisions |
| 4 | Coworker delegation | Bulk-context, docs across repos |
| 5 | Operator ask | True ambiguity OR hard-gated OR business strategy |

Канонический контракт — `skills/autonomous-mode/SKILL.md`. Бизнес-стратегические вопросы сразу идут к L5 (narrow mode) — safe-defaults не применяются.

### L1 Inline Resolution Rule

Discovered mid-cycle gaps классифицируются: single file × ≤50 LoC × no contract change × not hard-gated → **L1 Class A**, фиксится inline и логируется в `datarim/tasks/{TASK-ID}-auto-inline-log.md`. Всё остальное (multi-file / contract change / operating-model shift) → backlog item с источником `discovered-during-auto-{TASK-ID}`. Hard-gated actions (`autonomous-agents.md:30-32`) escalate to operator через L5 даже под /dr-auto.

### When to use

- Backlog items L1-L2 с явным acceptance criteria.
- Resume interrupted task (после crash или `/clear`).
- Pipeline dogfood и benchmarks — measure Q&A suppression rate.

### When NOT to use

- Exploratory задачи где operator intent нужно frequently refine.
- High-stakes Class B изменения framework operating-model — operator presence нужно на каждом stage gate.
- Cross-project orchestration — используй `/dr-orchestrate` plugin вместо.

### Failure modes

- **Env-var leak** после `/clear` — mismatch detection (env set, marker absent) → treat as non-auto с warning.
- **Marker stale** от crashed session — 24h TTL → silent purge.
- **Ladder false-confident** (L1-L4 нашли не тот answer) — ambiguity rule strict: ≥2 candidates → escalate up.

## Next Steps

- [Pipeline Stages](../explanation/pipeline.md) -- detailed reference for each of the 9 pipeline stages
- [Commands Reference](../reference/commands.md) -- all 28 available commands with usage examples
- [Backlog Workflow](../how-to/backlog-workflow.md) -- how to manage tasks, priorities, and the backlog
- [Complexity Routing](../reference/complexity.md) -- how task complexity determines which stages run

## Adding plugins (v1.23.0+)

Datarim ships with a built-in `datarim-core` set. Optional skills, agents, commands, and templates beyond core are managed via the `/dr-plugin` CLI.

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

For full reference see `commands/dr-plugin.md` and `templates/plugin.yaml.template`. Authoring third-party plugins: [plugin-author-guide.md](../explanation/plugin-author-guide.md).
