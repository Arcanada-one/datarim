---
name: dr-help
description: List all available Datarim commands with descriptions and usage guidance
---

# /dr-help — Datarim Command Reference

Show the user a complete reference of all available Datarim commands, the pipeline flow, and complexity routing.

## Pipeline Flow

```
init → prd → plan → design → do → qa → compliance → archive
```

Not every task goes through every stage. Datarim routes tasks based on complexity (see below). Reflection runs automatically as mandatory Step 0.5 inside `/dr-archive` (v1.10.0, TUNE-0013).

## Commands

### Pipeline Commands (8)

| Command | Stage | Description |
|---------|-------|-------------|
| `/dr-init` | Initialize | Start a new task, pick from backlog, or **scaffold a new project**. Assigns complexity (L1-L4) for tasks; for projects use `/dr-init create project "Name"`. |
| `/dr-prd` | Requirements | Generate a Product Requirements Document. Define scope, constraints, and success criteria. |
| `/dr-plan` | Planning | Create a detailed implementation plan. Break work into phases, estimate effort, identify risks. |
| `/dr-design` | Design | Explore architectural and design decisions. Evaluate alternatives, run consilium panels for L3-L4. |
| `/dr-do` | Execution | Execute the plan using TDD (for code) or structured iteration (for other work). |
| `/dr-qa` | Quality | Multi-layer quality verification: PRD alignment, design conformance, plan completeness, output quality. |
| `/dr-compliance` | Hardening | Post-QA hardening. 7-step workflow: revalidate, simplify, check references, coverage, lint, tests, harden. |
| `/dr-archive` | Archive | Archive the completed task. Performs reflection (Step 0.5) + evolution proposals, then stores context and updates backlog. |

### Content Commands (2)

| Command | Description |
|---------|-------------|
| `/dr-write` | Create written content — articles, blog posts, documentation, research papers, social media. Uses the **writer** agent with the writing workflow skill. |
| `/dr-edit` | Editorial review — fact verification, AI pattern removal, style consistency, publication-ready quality. Uses the **editor** agent with factcheck and humanize skills. |

### Framework Management Commands (3)

| Command | Description |
|---------|-------------|
| `/dr-addskill` | Create or update skills, agents, commands. Researches best practices, audits existing framework, generates artifacts in project or user scope. |
| `/dr-optimize` | Audit and optimize the framework. Prune unused components, merge duplicates, fix broken references, sync documentation. Run periodically or when the framework feels bloated. |
| `/dr-dream` | Knowledge base maintenance. Organize files, build index, cross-reference documents, flag contradictions, archive stale content. Run periodically or when the knowledge base feels messy. |

### Utility Commands (3)

| Command | Description |
|---------|-------------|
| `/dr-status` | Check current task status, pipeline progress, and backlog summary. Read-only. |
| `/dr-continue` | Resume work from the last checkpoint. Restores context and picks up where you left off. |
| `/dr-help` | Show this command reference. |

### Standalone Commands (2)

| Command | Description |
|---------|-------------|
| `/factcheck` | Fact-check a specific file. Extracts claims, verifies against sources, corrects errors. Use for quick targeted checks outside the full editorial pipeline. |
| `/humanize` | Remove AI writing patterns from a specific file. Fixes vocabulary, structure, and formatting artifacts. Use for quick targeted fixes outside the full editorial pipeline. |

## Content Workflow

For writing and editing tasks, use the content commands:

```
/dr-write → /dr-edit → [/dr-qa] → /dr-archive
```

Or within the standard pipeline:
```
/dr-init → /dr-prd → /dr-plan → /dr-write → /dr-edit → /dr-qa → /dr-archive
```

For quick one-off checks, use `/factcheck` or `/humanize` directly on any file.

## Complexity Routing

| Level | Name | Scope | Pipeline |
|-------|------|-------|----------|
| L1 | Quick Fix | 1 file, minor change | `init → do → archive` |
| L2 | Enhancement | 2-5 files | `init → [prd] → plan → do → [qa] → archive` |
| L3 | Feature | 5-15 files | `init → prd → plan → design → do → qa → [compliance] → archive` |
| L4 | Major | 15+ files | `init → prd → plan → design → phased-do → qa → compliance → archive` |

Stages in `[brackets]` are optional — included when the agent determines they add value. `archive` always runs reflection internally as mandatory Step 0.5 (v1.10.0, TUNE-0013).

## Agents (16)

| Agent | Role |
|-------|------|
| planner | Project management, task breakdown, complexity assessment |
| architect | System design, trade-offs, interfaces |
| developer | TDD implementation, code quality |
| tester | Platform QA, test runners, Docker-aware execution |
| reviewer | QA, security compliance, DoD validation |
| compliance | Post-QA hardening, PRD revalidation |
| code-simplifier | Reduce complexity, improve readability |
| strategist | Value/Risk/Cost evaluation |
| devops | CI/CD, infrastructure, deployment |
| writer | Content creation — articles, docs, research, posts |
| editor | Editorial review — factcheck, humanize, style |
| skill-creator | Create/update skills, agents, commands from descriptions |
| optimizer | Audit, prune, merge, optimize framework components |
| librarian | Organize knowledge base, build index, cross-reference |
| security | Threat modeling, vulnerability audit |
| sre | Reliability, observability, incident response |

## Backlog

Datarim tracks tasks in a two-file backlog system:
- `datarim/backlog.md` — active items (pending + in progress)
- `datarim/backlog-archive.md` — completed and cancelled items

Use `/dr-init` to pick a task from the backlog or create a new one.
Use `/dr-status` to see the backlog summary.

## Project Scaffolding

`/dr-init` can also scaffold a new project structure:

```
/dr-init create project "My API Service"
/dr-init новый проект "Мой сервис"
```

This creates: `CLAUDE.md`, `docs/` (architecture, testing, deployment, gotchas), `docs/ephemeral/` (plans, research, reviews), `datarim/` (workflow state), and `documentation/archive/`. Tech stack is auto-detected from project description via `tech-stack.md`.

Idempotent — safe to run on existing projects (skips existing files, creates only what is missing).

## Tips

- Start with `/dr-init <task description>` — the framework handles routing.
- Use `/dr-init create project "Name"` to scaffold a new project with full structure.
- Use `/dr-status` at any time to see where you are.
- Use `/dr-continue` after a break to resume with full context.
- Datarim works for any project type: software, research, documentation, legal, project management.
- Each task gets a unique ID (e.g., `TASK-0001`) for tracking across the pipeline.
- For content work, use `/dr-write` + `/dr-edit` instead of `/dr-do` + `/dr-qa`.
