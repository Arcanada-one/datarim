# Agents Reference

Datarim includes 11 specialized agents. Each agent is a persona with defined capabilities, context requirements, and skill dependencies.

## Agent Roster

| Agent | Role | Model | Primary Stages |
|-------|------|-------|----------------|
| planner | Lead Project Manager | opus | /init, /plan, /archive |
| architect | Chief Architect | opus | /prd, /design |
| developer | Senior Developer (TDD) | opus | /do |
| reviewer | QA & Security Lead | opus | /qa, /reflect |
| compliance | Compliance Runner | opus | /compliance |
| code-simplifier | Code Simplification | opus | /compliance |
| strategist | Strategic Advisor | opus | /plan (L3-4) |
| devops | DevOps Engineer | opus | /plan, /do, /compliance |
| writer | Technical Writer | opus | /reflect, /archive, /prd |
| security | Security Analyst | opus | /design, /qa, /compliance |
| sre | Site Reliability Engineer | opus | /design, /qa, /reflect |

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
- **Custom:** any 3-7 agents based on the question

See `skills/consilium.md` for the full panel discussion protocol.
