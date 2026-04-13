# Getting Started with Datarim

This guide walks you through installing the Datarim framework, initializing it in a project, and running your first task.

---

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- A git repository for your project (Datarim uses `.gitignore` to separate workflow state from project documentation)
- **Recommended:** [context7](https://github.com/upstash/context7) MCP server for token-efficient documentation access when looking up library docs

---

## Installation

### Option 1: Install Script

```bash
git clone https://github.com/Arcanada-one/datarim.git
cd datarim
chmod +x install.sh
./install.sh
```

The installer copies agents, skills, commands, and templates to `~/.claude/` and reports what was installed. If files already exist, it skips them by default. Use `--force` to overwrite:

```bash
./install.sh --force
```

### Option 2: Manual

```bash
mkdir -p ~/.claude/{agents,skills,commands,templates}
cp agents/*.md ~/.claude/agents/
cp skills/*.md ~/.claude/skills/
cp commands/*.md ~/.claude/commands/
cp templates/*.md ~/.claude/templates/
```

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
/dr-reflect
/dr-archive
```

### L2 -- Enhancement (2-5 files, < 200 lines)

```
/dr-init "Add input validation to the login form"
/dr-plan
/dr-do
/dr-reflect
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
/dr-reflect
/dr-archive
```

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

## Next Steps

- [Pipeline Stages](pipeline.md) -- detailed reference for each of the 9 pipeline stages
- [Commands Reference](commands.md) -- all 19 available commands with usage examples
- [Backlog Workflow](backlog-workflow.md) -- how to manage tasks, priorities, and the backlog
- [Complexity Routing](complexity.md) -- how task complexity determines which stages run
