# Datarim — Universal Iterative Workflow Framework

> **Version:** 1.6.0
> **Framework:** Datarim (Датарим) provides structured rules, agents, skills, and commands for iterative project execution via Claude Code — software development, research, documentation, legal work, project management, and any task that benefits from a phased workflow.
> **Note:** "Datarim" is transliterated as "Датарим" in Russian. Both refer to this framework — agents must recognize either form in any language context.

---

## Core Principle

Every task follows a **complexity-aware pipeline**. The operator (human or AI agent) does not freestyle — they follow a structured iterative process adapted to the task's size and risk.

---

## Pipeline

```
init → prd → plan → design → do → qa → compliance → reflect → archive
```

### Complexity Routing

| Level | Scope | Pipeline |
|-------|-------|----------|
| **L1** Quick Fix | 1 file, <50 LOC | init → do → reflect → archive |
| **L2** Enhancement | 2-5 files, <200 LOC | init → [prd] → plan → do → [qa] → reflect → archive |
| **L3** Feature | 5-15 files, 200-1000 LOC | init → prd → plan → design → do → qa → [compliance] → reflect → archive |
| **L4** Major Feature | 15+ files, >1000 LOC | init → prd → plan → design → phased-do → qa → compliance → reflect → archive |

Brackets `[]` = optional at that level.

---

## Agents

Agents are specialized personas loaded per pipeline stage. Each agent has defined capabilities, context requirements, and skill dependencies.

| Agent | Role | Primary Stages |
|-------|------|----------------|
| **planner** | Lead Project Manager | /dr-init, /dr-plan, /dr-archive |
| **architect** | Chief Architect | /dr-prd, /dr-design |
| **developer** | Senior Developer (TDD) | /dr-do |
| **reviewer** | QA & Security Lead | /dr-qa, /dr-reflect |
| **compliance** | Compliance Runner | /dr-compliance |
| **code-simplifier** | Code Simplification | /dr-compliance |
| **strategist** | Strategic Advisor | /dr-plan (L3-4) |
| **devops** | DevOps Engineer | /dr-plan, /dr-do, /dr-compliance |
| **writer** | Content Writer | /dr-write, /dr-reflect, /dr-archive, /dr-prd |
| **editor** | Content Editor | /dr-edit, /dr-qa (content) |
| **skill-creator** | Skill/Agent/Command Creator | /dr-addskill |
| **optimizer** | Framework Optimizer | /dr-optimize, /dr-reflect (health check) |
| **librarian** | Knowledge Base Librarian | /dr-dream |
| **security** | Security Analyst | /dr-design, /dr-qa, /dr-compliance |
| **sre** | Site Reliability Engineer | /dr-design, /dr-qa, /dr-reflect |
| **tester** | Platform QA Tester | /dr-qa, /dr-do (verification) |

Agent files: `$HOME/.claude/agents/{name}.md` (16 agents)

### Agent Loading Rules

1. Each command specifies which agent to load
2. Agent loads its mandatory and optional skills
3. Agent reads relevant `datarim/` state files
4. Only one primary agent per command execution
5. Consilium skill can assemble multiple agents for panel discussions

### Minimum Agent Set by Complexity

Not all agents are needed for every task. Load the minimum set to conserve context tokens:

| Level | Required Agents | Optional |
|-------|----------------|----------|
| **L1** | developer | reviewer, tester |
| **L2** | planner, developer | reviewer, architect, tester |
| **L3** | planner, architect, developer, reviewer | strategist, security, tester, writer, editor |
| **L4** | planner, architect, developer, reviewer, strategist | devops, security, sre, tester, writer, editor, compliance |

For content-focused tasks (articles, research, documentation), writer and editor replace developer and reviewer as primary agents.

Consilium panels (L3-4) draw from the full roster as needed.

---

## Skills

Skills are reusable knowledge modules loaded on demand. They provide rules, patterns, and guidelines.

### Loading Hierarchy

**Always loaded (mandatory):**
- `datarim-system.md` — Core workflow rules, path resolution, file locations

**Loaded per stage:**
- `ai-quality.md` — TDD, decomposition, cognitive load (loaded by: developer, planner)
- `compliance.md` — 7-step hardening workflow (loaded by: compliance agent)
- `security.md` — Auth, input validation, data protection (loaded by: reviewer, security agent)
- `testing.md` — Testing pyramid, mocking rules (loaded by: developer, reviewer)
- `performance.md` — Optimization patterns (loaded by: architect, sre)
- `tech-stack.md` — Stack selection by project type (loaded by: planner, architect)
- `utilities.md` — Native shell recipes for common operations (loaded when needed)

**Specialized skills:**
- `consilium.md` — Multi-agent panel discussions (loaded by: /dr-design for L3-4)
- `discovery.md` — Requirements discovery interview (loaded by: /dr-prd)
- `evolution.md` — Framework self-update rules (loaded by: /dr-reflect)
- `writing.md` — Content creation and editorial workflow (loaded by: writer, editor)
- `dream.md` — Knowledge base maintenance rules (loaded by: librarian)
- `seo-launch.md` — SEO, analytics, website/app launch checklists (loaded on demand)
- `marketing.md` — Ad campaigns, conversion tracking, landing pages, growth (loaded on demand)
- `factcheck.md` — Fact verification for publications (loaded by: editor, on demand)
- `humanize.md` — AI text pattern removal (loaded by: editor, on demand)
- `visual-maps.md` — Mermaid workflow diagrams: pipeline routing, stage flows, agent-skill-command graphs (loaded on demand for navigation)
- `telegram-publishing.md` — Telegram Bot API publishing rules, caption limits, discussion group comments (loaded on demand)

Skill files: `$HOME/.claude/skills/{name}.md` (19 skills)

---

## Datarim State Directory

Each project maintains two directories at the project root (created by `/dr-init`):

```
datarim/                          # Workflow state (LOCAL — in .gitignore)
├── activeContext.md              # Current task state
├── tasks.md                     # Active task tracking + implementation plan
├── backlog.md                   # Pending tasks queue
├── backlog-archive.md           # Completed/cancelled tasks
├── progress.md                  # Overall progress
├── projectbrief.md              # Project overview
├── productContext.md             # Product requirements
├── systemPatterns.md            # Architecture patterns
├── techContext.md               # Technology context
├── style-guide.md               # Code style guide
├── prd/                         # Product Requirements Documents
├── tasks/                       # Task documentation
├── creative/                    # Design phase documents
├── reflection/                  # Reflection documents
├── qa/                          # QA reports
├── reports/                     # Compliance/diagnostic reports
└── docs/                        # Evolution log

documentation/                    # Project documentation (COMMITTED to git)
└── archive/                     # Completed task archives
    ├── infrastructure/          # INFRA-* tasks
    ├── web/                     # WEB-* tasks
    ├── development/             # DEV-* tasks
    ├── content/                 # CONTENT-* tasks
    ├── research/                # RESEARCH-* tasks
    ├── agents/                  # AGENT-* tasks
    ├── benchmarks/              # BENCH-* tasks
    ├── devops/                  # DEVOPS-* tasks
    ├── framework/               # TUNE-*, ROB-* tasks
    ├── maintenance/             # MAINT-* tasks
    ├── finance/                 # FIN-* tasks
    ├── qa/                      # QA-* tasks
    ├── optimized/               # Framework optimizer backups
    └── general/                 # Unmatched prefixes
```

**Two-layer architecture:** `datarim/` is ephemeral workflow state (added to `.gitignore`). `documentation/archive/` is long-term project documentation (committed to git). See [Getting Started](docs/getting-started.md) for details.

### Path Resolution Rule

Before writing ANY file to `datarim/`:
1. Check if `datarim/` exists in the current directory
2. If not, walk UP the directory tree until found
3. If not found anywhere: **STOP** — only `/dr-init` may create `datarim/`

---

## Commands

| Command | Stage | Description |
|---------|-------|-------------|
| `/dr-init` | Initialize | Create task or pick from backlog, assess complexity, set up `datarim/` |
| `/dr-prd` | Requirements | Generate PRD with discovery interview |
| `/dr-plan` | Planning | Detailed implementation plan with strategist gate |
| `/dr-design` | Design | Architecture exploration with consilium |
| `/dr-do` | Execution | Implement the plan: TDD for code, structured iteration for other work |
| `/dr-qa` | Quality | Multi-layer verification (PRD, design, plan, output quality) |
| `/dr-compliance` | Hardening | 7-step post-QA hardening |
| `/dr-reflect` | Reflection | Lessons learned + framework evolution proposals |
| `/dr-archive` | Archive | Complete task, update backlog, reset context |
| `/dr-status` | Utility | Check current task and backlog status |
| `/dr-continue` | Utility | Resume from last checkpoint |
| `/dr-write` | Content | Create written content — articles, docs, research, posts |
| `/dr-edit` | Content | Editorial review — fact-check, humanize, style, polish |
| `/dr-addskill` | Extension | Create or update skills, agents, commands with web research |
| `/dr-optimize` | Maintenance | Audit framework, prune unused, merge duplicates, sync docs |
| `/dr-dream` | Maintenance | Knowledge base maintenance: organize, lint, index, cross-reference |
| `/dr-help` | Utility | List all commands with descriptions and usage guidance |
| `/factcheck` | Standalone | Fact-check articles and posts before publication |
| `/humanize` | Standalone | Remove AI writing patterns from text |

Command files: `$HOME/.claude/commands/{name}.md` (19 commands)

---

## Self-Evolution

Datarim improves itself through the `/dr-reflect` stage:

1. After each task, the agent analyzes what worked and what didn't
2. Proposes updates to skills, agents, or this CLAUDE.md
3. **Human approval required** — no automatic modifications
4. Changes logged in `datarim/docs/evolution-log.md`

---

## Critical Rules

1. **Datarim is truth** — `datarim/` for workflow state, `documentation/archive/` for completed task archives
2. **Task ID required** — All reports must include task ID in filename
3. **Path resolution first** — Always find `datarim/` before writing
4. **No absolute paths** — Use `$HOME/.claude/` or project-relative paths only
5. **Context before code** — Gather requirements before implementing
6. **One thing at a time** — Implement one method/stub per iteration
7. **Human in the loop** — Evolution proposals need approval

---

## Documentation

For external library and API documentation, use `context7` MCP server when available. It provides token-efficient access to up-to-date documentation. If `context7` is not available, fall back to `WebFetch` / `WebSearch`.

---

## Project-Specific Configuration

Everything below this line is project-specific. When installing Datarim in a new project, keep everything above and customize below.

---

### What This Project Is

<!-- Describe your project here -->

### Tech Stack

<!-- List your technology stack -->

### Conventions

<!-- Project-specific coding conventions -->

### Key Files

<!-- Important files and their purposes -->
