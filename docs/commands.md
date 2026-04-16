# Commands Reference

Datarim provides 18 slash commands for Claude Code. Commands are grouped by category.

## Pipeline Commands (8)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-init` | Initialize | planner | Create task, assess complexity, set up `datarim/` |
| `/dr-prd` | Requirements | architect | Generate PRD with discovery interview |
| `/dr-plan` | Planning | planner | Detailed implementation plan with strategist gate |
| `/dr-design` | Design | architect | Architecture exploration with consilium (L3-4) |
| `/dr-do` | Execution | developer | TDD development, one method at a time |
| `/dr-qa` | Quality | reviewer | Multi-layer verification (PRD, design, plan, code) |
| `/dr-compliance` | Hardening | compliance | 7-step post-QA hardening workflow |
| `/dr-archive` | Archive | reviewer (Step 0.5 reflection) + planner (Steps 1-7) | Reflection + evolution proposals + complete task + update backlog + reset context |

## Content Commands (2)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-write` | Content | writer | Create written content -- articles, docs, research, posts |
| `/dr-edit` | Content | editor | Editorial review -- fact-check, humanize, style, polish |

## Framework Management (3)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-addskill` | Extension | skill-creator | Create or update skills, agents, commands with web research |
| `/dr-optimize` | Maintenance | optimizer | Audit framework, prune unused, merge duplicates, sync docs |
| `/dr-dream` | Maintenance | librarian | Knowledge base maintenance: organize, lint, index, cross-reference |

## Utility Commands (3)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-status` | Utility | -- | Check current task and backlog status (read-only) |
| `/dr-continue` | Utility | -- | Resume from last checkpoint |
| `/dr-help` | Utility | -- | List all commands with descriptions and usage guidance |

## Standalone Commands (2)

| Command | Agent | Description |
|---------|-------|-------------|
| `/factcheck` | -- | Fact-check articles and posts before publication |
| `/humanize` | -- | Remove AI writing patterns from text |

## Command File Format

```markdown
---
name: {command-name}
description: {one-line description}
---

# /{command} -- {Title}

**Role**: {Agent Name}
**Source**: `$HOME/.claude/agents/{agent}.md`

## Instructions
0. **RESOLVE PATH**: Find datarim/ directory
1. **LOAD**: Read agent persona
2. **CONTEXT**: Read relevant datarim/ files
3. **ACTION**: Execute stage logic
4. **OUTPUT**: Results + next steps
```

## Usage Examples

```bash
# Start a new task
/dr-init Add rate limiting to the API

# Generate requirements (for L2+ tasks)
/dr-prd

# Create implementation plan
/dr-plan

# Start coding
/dr-do

# Run quality checks
/dr-qa

# Check progress anytime
/dr-status

# Resume after a break
/dr-continue

# Write a blog post
/dr-write Create a blog post about our new API versioning strategy

# Editorial review of content
/dr-edit Review the blog post for publication readiness

# Add a new skill to the framework
/dr-addskill Create an accessibility skill covering WCAG 2.1 AA

# Audit and optimize the framework
/dr-optimize

# Organize and consolidate the knowledge base
/dr-dream
```
