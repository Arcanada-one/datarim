# Agents Reference

Datarim includes 16 specialized agents. Each agent is a persona with defined capabilities, context requirements, and skill dependencies. Each agent runs on a specific Claude model — see [Model Assignment Convention](../skills/datarim-system.md) (in skill `datarim-system.md`) for the rationale.

## Agent Roster

| Agent | Role | Model | Primary Stages |
|-------|------|-------|----------------|
| planner | Lead Project Manager | opus | /dr-init, /dr-plan, /dr-archive |
| architect | Chief Architect | opus | /dr-prd, /dr-design |
| strategist | Strategic Advisor | opus | /dr-plan (L3-4) |
| security | Security Analyst | opus | /dr-design, /dr-qa, /dr-compliance |
| reviewer | QA & Security Lead | opus | /dr-qa, /dr-reflect |
| skill-creator | Skill/Agent/Command Creator | opus | /dr-addskill |
| developer | Senior Developer (TDD) | sonnet | /dr-do |
| compliance | Compliance Runner | sonnet | /dr-compliance |
| code-simplifier | Code Simplification | sonnet | /dr-compliance |
| devops | DevOps Engineer | sonnet | /dr-plan, /dr-do, /dr-compliance |
| editor | Content Editor | sonnet | /dr-edit, /dr-qa (content) |
| librarian | Knowledge Base Librarian | sonnet | /dr-dream |
| optimizer | Framework Optimizer | sonnet | /dr-optimize, /dr-reflect |
| sre | Site Reliability Engineer | sonnet | /dr-design, /dr-qa, /dr-reflect |
| writer | Content Writer | sonnet | /dr-write, /dr-reflect, /dr-archive, /dr-prd |
| tester | Platform QA Tester | haiku | /dr-qa, /dr-do (verification) |

**Distribution:** 6 opus (critical reasoning), 9 sonnet (standard work), 1 haiku (test execution).

## Agent File Format

All agents follow this structure:

```markdown
---
name: {agent-name}
description: {one-line description}
model: opus  # or sonnet, haiku — REQUIRED, see Model Assignment Convention
---

You are the **{Role Title}**.
Your goal is to {primary goal}.

**Capabilities**: (bullet list)

**Context Loading**:
- READ: datarim/{files}
- ALWAYS APPLY: $HOME/.claude/skills/{mandatory-skills}
- LOAD WHEN NEEDED: $HOME/.claude/skills/{optional-skills}
```

The `model` field is required for all agents. Choose per [Model Assignment Convention](../skills/datarim-system.md).

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
