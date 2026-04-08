# Datarim — SDLC Framework for AI Agentic Systems

> **Version:** 1.0
> **Framework:** Datarim provides structured rules, agents, skills, and commands for autonomous AI-driven software development via Claude Code.

---

## Core Principle

Every task follows a **complexity-aware pipeline**. The AI agent does not freestyle — it follows a structured SDLC process adapted to the task's size and risk.

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
| **writer** | Technical Writer | /dr-reflect, /dr-archive, /dr-prd |
| **security** | Security Analyst | /dr-design, /dr-qa, /dr-compliance |
| **sre** | Site Reliability Engineer | /dr-design, /dr-qa, /dr-reflect |

Agent files: `$HOME/.claude/agents/{name}.md`

### Agent Loading Rules

1. Each command specifies which agent to load
2. Agent loads its mandatory and optional skills
3. Agent reads relevant `datarim/` state files
4. Only one primary agent per command execution
5. Consilium skill can assemble multiple agents for panel discussions

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
- `factcheck.md` — Fact verification for publications (loaded on demand)
- `humanize.md` — AI text pattern removal (loaded on demand)

Skill files: `$HOME/.claude/skills/{name}.md`

---

## Datarim State Directory

Each project maintains a `datarim/` directory at the project root (created by `/dr-init`).

```
datarim/
├── activeContext.md       # Current task state
├── tasks.md              # Active task tracking + implementation plan
├── backlog.md            # Pending tasks queue
├── backlog-archive.md    # Completed/cancelled tasks
├── progress.md           # Overall progress
├── projectbrief.md       # Project overview
├── productContext.md      # Product requirements
├── systemPatterns.md     # Architecture patterns
├── techContext.md        # Technology context
├── style-guide.md        # Code style guide
├── prd/                  # Product Requirements Documents
├── tasks/                # Task documentation
├── creative/             # Design phase documents
├── reflection/           # Reflection documents
├── qa/                   # QA reports
├── reports/              # Compliance/diagnostic reports
├── archive/              # Completed task archives
└── docs/                 # Evolution log
```

### Path Resolution Rule

Before writing ANY file to `datarim/`:
1. Check if `datarim/` exists in the current directory
2. If not, walk UP the directory tree until found
3. If not found anywhere: **STOP** — only `/dr-init` may create `datarim/`

---

## Commands

| Command | Stage | Description |
|---------|-------|-------------|
| `/dr-init` | Initialize | Create task, assess complexity, set up `datarim/` |
| `/dr-prd` | Requirements | Generate PRD with discovery interview |
| `/dr-plan` | Planning | Detailed implementation plan with strategist gate |
| `/dr-design` | Design | Architecture exploration with consilium |
| `/dr-do` | Implementation | TDD development, one method at a time |
| `/dr-qa` | Quality | Multi-layer verification (PRD, design, plan, code) |
| `/dr-compliance` | Hardening | 7-step post-QA hardening |
| `/dr-reflect` | Reflection | Lessons learned + framework evolution proposals |
| `/dr-archive` | Archive | Complete task, update backlog, reset context |
| `/dr-status` | Utility | Check current task and backlog status |
| `/dr-continue` | Utility | Resume from last checkpoint |

Command files: `$HOME/.claude/commands/{name}.md`

---

## Self-Evolution

Datarim improves itself through the `/dr-reflect` stage:

1. After each task, the agent analyzes what worked and what didn't
2. Proposes updates to skills, agents, or this CLAUDE.md
3. **Human approval required** — no automatic modifications
4. Changes logged in `datarim/docs/evolution-log.md`

---

## Critical Rules

1. **Datarim is truth** — All task state lives in `datarim/`, not in conversation memory
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
