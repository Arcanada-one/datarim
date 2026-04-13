---
name: datarim-system
description: Core workflow rules — file locations, task numbering, path resolution, backlog format, complexity routing. Always loaded.
---

# Datarim System Rules

> **Core system rules for Datarim (датарим) workflow and file organization. Always loaded.**
> "Datarim" and "датарим" are the same framework. Recognize both forms in any language context.

## File Locations

**CRITICAL:** All Datarim state files reside in `datarim/` directory at the **project root** (the top-level git repository root, NOT a submodule or subdirectory).

### Path Resolution Rule (MANDATORY)

Before writing ANY file to `datarim/`, you MUST resolve the correct path:

1. **Check if `datarim/` exists in the current working directory.** If yes, use it.
2. **If NOT found:** Walk up the directory tree (parent, grandparent, etc.) until you find a directory that contains `datarim/`. Use that path.
3. **If still NOT found anywhere up the tree:** **STOP. Do NOT create the directory.** Only the `/dr-init` command is authorized to create a new `datarim/` directory. If you are not running `/dr-init`, output an error: _"datarim/ directory not found. Run `/dr-init` first to initialize it in the correct project root."_

**Why:** In monorepos and submodule setups, the working directory may be a subdirectory. Creating `datarim/` there pollutes the subproject. The correct location is always the top-level project root.

**Quick shell check (use before any write):**
```bash
DR_DIR=$(pwd); while [ "$DR_DIR" != "/" ]; do [ -d "$DR_DIR/datarim" ] && break; DR_DIR=$(dirname "$DR_DIR"); done
if [ "$DR_DIR" = "/" ]; then echo "ERROR: datarim/ not found"; else echo "$DR_DIR/datarim"; fi
```

### Core Files
- `tasks.md` — Active task tracking (ephemeral)
- `backlog.md` — Active task queue (v2.0 — performance optimized)
- `backlog-archive.md` — Historical completed/cancelled tasks
- `activeContext.md` — Current state
- `progress.md` — Overall progress
- `projectbrief.md` — Project overview
- `productContext.md` — Product requirements
- `systemPatterns.md` — System patterns
- `techContext.md` — Technical context
- `style-guide.md` — Code style guide

### Directories
- `prd/` — Product Requirements Documents
- `tasks/` — ALL operational task documentation
- `creative/` — Creative phase documents
- `reflection/` — Reflection documents
- `qa/` — QA reports
- `reports/` — Debug/diagnostic reports
- `docs/` — Framework evolution log and documentation

### Documentation Directory (project-level, alongside `datarim/`)

Completed task archives live **outside** `datarim/`, in `documentation/archive/{area}/`. This separation reflects two layers:

- **`datarim/`** — ephemeral workflow state (tasks, backlog, activeContext). Added to `.gitignore`. Stays on developer's local machine.
- **`documentation/archive/`** — long-term project documentation. Committed to git. Task archives with goals, decisions, and implementation details become the project's knowledge base.

```
documentation/
└── archive/
    ├── infrastructure/    # INFRA-* tasks
    ├── web/               # WEB-* tasks
    ├── content/           # CONTENT-* tasks
    ├── research/          # RESEARCH-* tasks
    ├── agents/            # AGENT-* tasks
    ├── benchmarks/        # BENCH-* tasks
    ├── development/       # DEV-* tasks
    ├── devops/            # DEVOPS-* tasks
    ├── framework/         # TUNE-*, ROB-* tasks
    ├── maintenance/       # MAINT-* tasks
    ├── finance/           # FIN-* tasks
    ├── qa/                # QA-* tasks
    ├── optimized/         # Framework optimizer backups
    └── general/           # Unmatched prefixes
```

---

## Documentation Storage Rules

### MANDATORY: Task ID in ALL Report Filenames

**Format:** `{PREFIX}-{NNNN}` (e.g., `TASK-0001`, `FIN-0001`) — see Unified Task Numbering below

**Report Types:**
- QA reports: `qa-report-[task_id]-[phase].md`
- Compliance reports: `compliance-report-[task_id]-[date].md`
- Test reports: `test-report-[task_id]-[component].md`
- Debug reports: `debug-[task_id]-[feature].md`
- Creative: `creative-[task_id]-[feature_name].md`

### Prohibited Locations

**NEVER create MD files (except README.md) in:**
- Application source directories
- Component directories (`frontend/src/`, `backend/src/`)
- Service root directories (except README.md)
- Any directory containing source code

---

## Task Numbering System

### Format
```
{PREFIX}-{NNNN}
```

**Examples:**
- `TASK-0001` (General task #1)
- `FIN-0001` (Finance task #1)
- `QA-0008` (QA task #8)

### Auto-Generation
If user doesn't provide task ID, system automatically:
1. Determines prefix from task content/keywords
2. Scans existing tasks for same prefix
3. Generates next sequential number (4-digit with leading zeros)

### Task ID Extraction
Get current task ID from `datarim/activeContext.md` first line:
```markdown
**Current Task:** [TASK-ID] - [Task Title]
```

---

## Task Context Tracking

### Active Task Identification

`activeContext.md` MUST track current task:

```markdown
**Current Task:** [TASK-ID] - [Task Title]
- **Status**: [in_progress|completed|paused]
- **Started**: [Date]
- **Complexity**: Level [1-4]
- **Type**: [Type]
- **Priority**: [Priority]
- **Repository**: [Repository]
- **Branch**: [Branch name]
```

### Task Status Lifecycle
```
not_started → in_progress → completed → archived
     ↓              ↑
   paused ←────────┘
```

### Archive Command Behavior
`/dr-archive` command:
1. Reads `activeContext.md` to get current task ID
2. Verifies task exists in `tasks.md`
3. Archives ONLY that specific task (not all completed)
4. Updates `activeContext.md` after archiving

---

## Unified Task Numbering (Invariant ID)

**Core principle:** A task's ID is assigned once and remains unchanged across its entire lifecycle:

```
backlog.md → tasks.md → documentation/archive/ → backlog-archive.md
```

The same ID `{PREFIX}-{NNNN}` appears in every document referencing this task — no renumbering when a backlog item becomes active, no separate `BACKLOG-XXXX` namespace.

### Prefix Selection (priority order)

1. **Project prefix** — if the task belongs to one specific project
2. **Area prefix** — if the task is cross-project or general
3. **`TASK`** — fallback (avoid if possible)

### Prefix Registry

**Project prefixes** (scoped to one project):

| Prefix | Project |
|--------|---------|
| `ARCA` | Arcanada Ecosystem core |
| `VERD` | Verdicus |
| `DATA` | Datarim framework |
| `CONS` | Consilium |
| `SUP` | Support Center |
| `ROB` | Rules of Robotics |
| `VOICE` | Voice Agent |
| `OVER` | Overlook |

**Area prefixes** (cross-project or general):

| Prefix | Area |
|--------|------|
| `INFRA` | Servers, DNS, SSL, cloud infrastructure |
| `WEB` | Websites, landing pages |
| `DEV` | Application code development |
| `DEVOPS` | CI/CD, pipelines, automation |
| `CONTENT` | Articles, posts, social media |
| `RESEARCH` | Analysis, literature review |
| `AGENT` | AI agents |
| `BENCH` | Benchmarks, performance tests |
| `MAINT` | Workspace scans, maintenance |
| `FIN` | Finance, legal |
| `QA` | Standalone QA work |
| `TUNE` | Datarim framework self-improvement |

### Deprecated: `BACKLOG-XXXX`

The generic `BACKLOG-XXXX` format is deprecated. New backlog items use project/area prefix directly. Historical `BACKLOG-XXXX` references in completed archives and reports remain for historical accuracy.

### Rename Policy

A task ID changes **only** by explicit request from user or agent. When renamed, all references in the knowledge base must be updated atomically.

---

## Model Assignment Convention

Each agent and task-skill MUST specify a `model` field in YAML frontmatter to optimize cost without sacrificing quality. This follows the official Anthropic Claude Code spec (https://code.claude.com/docs/en/sub-agents and /skills).

### Available values

| Value | Behavior |
|-------|----------|
| `opus` | Most capable, highest cost. Use for critical reasoning. |
| `sonnet` | Balanced capability/cost. Default for most work. |
| `haiku` | Fast, low cost. Use for simple structured tasks. |
| `<full-id>` | E.g., `claude-opus-4-6` for pinning a specific version. |
| `inherit` | Use caller's model. Default for reference skills. |

### Decision matrix

| Use **opus** when... | Use **sonnet** when... | Use **haiku** when... |
|----------------------|------------------------|------------------------|
| Architectural decisions | Standard code/content work | Simple lookups |
| Security analysis | Structured tasks (checklists) | Test execution |
| Strategic evaluation | Editorial review | API calls |
| Multi-perspective debate | Knowledge maintenance | Mechanical output |
| Critical reasoning | Standard QA | Shell utilities |

### Reference vs task content (skills only)

- **Reference skills** (rules, patterns, guidelines applied inline): omit `model` — it inherits from caller. Examples: `datarim-system`, `ai-quality`, `security`, `testing`, `performance`, `tech-stack`.
- **Task skills** (perform an action when invoked): set `model` explicitly. Examples: `dream`, `consilium`, `factcheck`, `humanize`.

### Effort field (additional lever)

Both agent and skill frontmatter support `effort: low|medium|high|max`. Use `effort: max` (Opus 4.6 only) for very complex one-off tasks. Default: inherits from session.

### Current assignments (v1.6.0)

**Agents (16):**
- **opus (6):** architect, planner, strategist, security, reviewer, skill-creator
- **sonnet (9):** developer, compliance, code-simplifier, devops, editor, librarian, optimizer, sre, writer
- **haiku (1):** tester

**Task-skills (14):**
- **opus (3):** consilium, evolution, incident-investigation
- **sonnet (9):** discovery, compliance, dream, factcheck, humanize, marketing, seo-launch, visual-maps, writing
- **haiku (2):** telegram-publishing, utilities

**Reference skills (6, no model):** datarim-system, ai-quality, security, testing, performance, tech-stack

---

## Backlog Management (v2.0)

### Two-File Architecture

**Active Backlog** (`backlog.md`):
- Contains ONLY `pending` and `in_progress` items
- Performance optimized (~10x faster reads)
- Format: `{PREFIX}-{NNNN}` (same ID the task will have — see Unified Task Numbering above)

**Backlog Archive** (`backlog-archive.md`):
- Historical `completed` and `cancelled` items
- Rarely read during normal operations
- Provides historical reference

### When to Update
- Task completion: Move from `backlog.md` to `backlog-archive.md`
- New task: Add to `backlog.md` with `pending` status

---

## Complexity Decision Tree

### Level 1 (Quick Fix)
- Single file change
- < 50 lines of code
- No architecture changes
- Flow: init → do → reflect → archive

### Level 2 (Enhancement)
- Few files (2-5)
- < 200 lines of code
- Minor refactoring
- Flow: init → plan → do → reflect → archive

### Level 3 (Feature)
- Multiple files (5-15)
- 200-1000 lines
- Requires design
- Flow: init → prd → plan → design → do → qa → reflect → archive

### Level 4 (Major Feature)
- Many files (15+)
- > 1000 lines
- Complex architecture
- Flow: init → prd → plan → design → phased-do → qa → compliance → reflect → archive

---

## Date Handling

For dates in filenames and reports, use native shell commands:
```bash
date +%Y-%m-%d          # 2026-04-09
date -u +%Y-%m-%dT%H:%M:%SZ  # UTC ISO 8601
```
Or use the current date from conversation context. See `$HOME/.claude/skills/utilities.md` for additional utility recipes.

---

## Mode Transition Optimization

### Automatic Transitions
- Level 3-4 → Auto-enter CREATIVE mode (/dr-design)
- QA validation needed → Auto-enter QA mode (/dr-qa)
- Implementation done → Auto-suggest REFLECT mode

### Manual Transitions
- `/dr-plan` → PLAN mode
- `/dr-design` → CREATIVE mode
- `/dr-do` → DO mode
- `/dr-qa` → QA mode
- `/dr-reflect` → REFLECT mode
- `/dr-archive` → ARCHIVE mode

---

## Namespace Rules

### Command Prefix: `/dr-`

All Datarim commands use the `/dr-` prefix (e.g., `/dr-init`, `/dr-plan`, `/dr-do`).

**Why:** Claude Code has built-in commands (`/init`, `/status`, `/continue`, `/plan`) that would conflict with bare names. The `/dr-` prefix ensures Datarim commands never shadow built-in functionality.

**Reserved names (DO NOT use as command names):**
`/init`, `/status`, `/continue`, `/plan`, `/clear`, `/help`, `/model`, `/compact`, `/config`, `/exit`, `/login`, `/resume`

**Naming convention for new commands:**
- Always prefix with `/dr-`
- Use lowercase kebab-case: `/dr-my-command`
- Keep names short (1-2 words after prefix)

---

## Archive Area Mapping

When archiving a task, determine the target subdirectory by extracting the prefix from the task ID:

| Prefix | Area Subdirectory |
|--------|------------------|
| `INFRA` | `infrastructure/` |
| `WEB` | `web/` |
| `CONTENT` | `content/` |
| `RESEARCH` | `research/` |
| `AGENT` | `agents/` |
| `BENCH` | `benchmarks/` |
| `DEV` | `development/` |
| `DEVOPS` | `devops/` |
| `TUNE` | `framework/` |
| `ROB` | `framework/` |
| `MAINT` | `maintenance/` |
| `FIN` | `finance/` |
| `QA` | `qa/` |
| *(unknown)* | `general/` |

**Logic:**
1. Extract PREFIX from task ID (everything before the first `-`)
2. Look up PREFIX in the table above
3. If not found → use `general/`

**Archive file path:** `documentation/archive/{area}/archive-{task_id}.md`

---

## Project Setup

When Datarim is initialized in a project (`/dr-init`):

1. **`datarim/`** is created at the project root for workflow state
2. **`documentation/archive/`** is created for long-term task archives
3. **`datarim/`** is added to `.gitignore` — workflow state is local, not shared
4. **`documentation/`** is committed — archives are project documentation

This allows:
- Multiple developers to work in parallel (each with their own `datarim/`)
- Project managers to read `documentation/archive/` for progress and decisions
- Clean git history — no ephemeral workflow files

---

## Critical Rules (Always Apply)

1. **Datarim is Truth** — `datarim/` for workflow state, `documentation/archive/` for completed task archives
2. **Task ID Required** — ALL reports must include task ID
3. **No documentation/tasks/** — This directory must NOT exist
4. **Context Tracking** — Always update `activeContext.md`
5. **Backlog v2.0** — Use two-file architecture (active + archive)
6. **Path Resolution First** — Always find `datarim/` before writing
7. **No Absolute Paths** — Use `$HOME/.claude/` or project-relative only

---

*These rules ensure clean organization and efficient workflow.*
