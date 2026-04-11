# Agents Reference

Datarim includes 15 specialized agents. Each agent is a persona with defined capabilities, context requirements, and skill dependencies.

## Agent Roster

| Agent | Role | Model | Primary Stages |
|-------|------|-------|----------------|
| planner | Lead Project Manager | opus | /dr-init, /dr-plan, /dr-archive |
| architect | Chief Architect | opus | /dr-prd, /dr-design |
| developer | Senior Developer (TDD) | opus | /dr-do |
| reviewer | QA & Security Lead | opus | /dr-qa, /dr-reflect |
| compliance | Compliance Runner | opus | /dr-compliance |
| code-simplifier | Code Simplification | opus | /dr-compliance |
| strategist | Strategic Advisor | opus | /dr-plan (L3-4) |
| devops | DevOps Engineer | opus | /dr-plan, /dr-do, /dr-compliance |
| writer | Content Writer | opus | /dr-write, /dr-reflect, /dr-archive, /dr-prd |
| editor | Content Editor | opus | /dr-edit, /dr-qa (content) |
| skill-creator | Skill/Agent/Command Creator | opus | /dr-addskill |
| optimizer | Framework Optimizer | opus | /dr-optimize, /dr-reflect |
| librarian | Knowledge Base Librarian | opus | /dr-dream |
| security | Security Analyst | opus | /dr-design, /dr-qa, /dr-compliance |
| sre | Site Reliability Engineer | opus | /dr-design, /dr-qa, /dr-reflect |

## Agent File Format

All agents follow this structure:

```markdown
---
name: {agent-name}
description: {one-line description}
model: opus
---

You are the **{Role Title}**.
Your goal is to {primary goal}.

**Capabilities**: (bullet list)

**Context Loading**:
- READ: datarim/{files}
- ALWAYS APPLY: $HOME/.claude/skills/{mandatory-skills}
- LOAD WHEN NEEDED: $HOME/.claude/skills/{optional-skills}
```

## Consilium Panels

Agents can be assembled into panels for multi-perspective analysis:

- **Architecture panel:** architect + strategist + security + sre + devops
- **Code panel:** developer + reviewer + code-simplifier
- **Production panel:** sre + devops + security
- **Feature panel:** strategist + architect + developer + writer
- **Content panel:** writer + editor
- **Knowledge panel:** librarian + architect + writer
- **Custom:** any 3-7 agents based on the question

See `skills/consilium.md` for the full panel discussion protocol.
