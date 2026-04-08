# Commands Reference

Datarim provides 11 slash commands for Claude Code. Each command drives one pipeline stage.

## Command Catalog

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/init` | Initialize | planner | Create task, assess complexity, set up `datarim/` |
| `/prd` | Requirements | architect | Generate PRD with discovery interview |
| `/plan` | Planning | planner | Detailed implementation plan with strategist gate |
| `/design` | Design | architect | Architecture exploration with consilium (L3-4) |
| `/do` | Implementation | developer | TDD development, one method at a time |
| `/qa` | Quality | reviewer | Multi-layer verification (PRD, design, plan, code) |
| `/compliance` | Hardening | compliance | 7-step post-QA hardening workflow |
| `/reflect` | Reflection | reviewer | Lessons learned + framework evolution proposals |
| `/archive` | Archive | planner | Complete task, update backlog, reset context |
| `/status` | Utility | — | Check current task and backlog status (read-only) |
| `/continue` | Utility | — | Resume from last checkpoint |

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
/init Add rate limiting to the API

# Generate requirements (for L2+ tasks)
/prd

# Create implementation plan
/plan

# Start coding
/do

# Run quality checks
/qa

# Check progress anytime
/status

# Resume after a break
/continue
```
