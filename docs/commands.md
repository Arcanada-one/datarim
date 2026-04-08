# Commands Reference

Datarim provides 11 slash commands for Claude Code. Each command drives one pipeline stage.

## Command Catalog

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-init` | Initialize | planner | Create task, assess complexity, set up `datarim/` |
| `/dr-prd` | Requirements | architect | Generate PRD with discovery interview |
| `/dr-plan` | Planning | planner | Detailed implementation plan with strategist gate |
| `/dr-design` | Design | architect | Architecture exploration with consilium (L3-4) |
| `/dr-do` | Implementation | developer | TDD development, one method at a time |
| `/dr-qa` | Quality | reviewer | Multi-layer verification (PRD, design, plan, code) |
| `/dr-compliance` | Hardening | compliance | 7-step post-QA hardening workflow |
| `/dr-reflect` | Reflection | reviewer | Lessons learned + framework evolution proposals |
| `/dr-archive` | Archive | planner | Complete task, update backlog, reset context |
| `/dr-status` | Utility | — | Check current task and backlog status (read-only) |
| `/dr-continue` | Utility | — | Resume from last checkpoint |

## Command File Format

```markdown
---
name: {command-name}
description: {one-line description}
---

# /{command} — {Title}

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
```
