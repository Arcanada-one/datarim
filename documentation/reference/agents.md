# Agents Reference

Datarim includes 20 specialized agents. Each agent is a persona with defined capabilities, context requirements, and skill dependencies.

Every shipped agent declares `model: inherit` — the operator's session model wins — plus a `metadata.model_tier:` capability intent. Tiers resolve to concrete models through `config/model-tiers.yaml`; see [Model Assignment Convention](../../skills/datarim-system/SKILL.md) (in skill `datarim-system.md`) for the rationale. The **Tier** column below is that capability intent, not a pinned model generation.

## Agent Roster

| Agent | Role | Tier | Primary Stages |
|-------|------|------|----------------|
| planner | Lead Project Manager | reasoning | /dr-init, /dr-plan, /dr-archive |
| architect | Chief Architect | reasoning | /dr-prd, /dr-design |
| strategist | Strategic Advisor | reasoning | /dr-plan (L3-4; redundancy-only or ambiguous L1-L2) |
| security | Security Analyst | reasoning | /dr-design, /dr-qa, /dr-compliance |
| reviewer | QA & Security Lead | reasoning | /dr-qa, /dr-archive (Step 0.5 reflection) |
| skill-creator | Skill/Agent/Command Creator | reasoning | /dr-addskill |
| designer | Frontend Design Lead | reasoning | Pre-code customer-facing frontend design and Knowledge Contract handoff |
| developer | Senior Developer (TDD) | balanced | /dr-do |
| compliance | Compliance Runner | balanced | /dr-compliance |
| code-simplifier | Code Simplification | balanced | /dr-compliance |
| devops | DevOps Engineer | balanced | /dr-plan, /dr-do, /dr-compliance |
| editor | Content Editor | balanced | /dr-edit, /dr-qa (content) |
| librarian | Knowledge Base Librarian | balanced | /dr-dream |
| optimizer | Framework Optimizer | balanced | /dr-optimize, /dr-archive (Step 0.5 health-check) |
| sre | Site Reliability Engineer | balanced | /dr-design, /dr-qa, /dr-archive (Step 0.5 postmortem) |
| writer | Content Writer | balanced | /dr-write, /dr-archive (Step 0.5 documentation review + final docs), /dr-prd |
| researcher | Structured External Research | balanced | /dr-prd (Phase 1.3), /dr-do (Gap Discovery) |
| peer-reviewer | Adversarial Peer Reviewer (Layer 2/3 fallback) | balanced | /dr-verify (cross-Claude-family fallback subagent) |
| dr-orchestrate-resolver | Plugin-backed subagent inference layer — classifies an unknown orchestrator pane line into a slash command via a multi-backend AI CLI chain (coworker → claude → codex). Fail-closed; threshold gating lives in the caller. Non-functional without the `dr-orchestrate` plugin's `subagent_resolver.sh` | balanced | /dr-orchestrate (unknown-prompt inference) |
| tester | Platform QA Tester | fast | /dr-qa, /dr-do (verification) |

**Distribution:** 7 reasoning (critical judgment), 12 balanced (standard work, review, and inference), 1 fast (test execution).

## Agent File Format

All agents follow this structure:

```markdown
---
name: {agent-name}
description: {one-line description}
model: inherit          # REQUIRED — see Model Assignment Convention
metadata:
  model_tier: balanced  # reasoning | balanced | fast | cheap
---

You are the **{Role Title}**.
Your goal is to {primary goal}.

**Capabilities**: (bullet list)

**Context Loading**:
- READ: datarim/{files}
- ALWAYS APPLY: $HOME/.claude/skills/{mandatory-skills}
- LOAD WHEN NEEDED: $HOME/.claude/skills/{optional-skills}
```

The `model` field is required for all agents and is `inherit` for every shipped agent — pinning a concrete model generation here breaks under runtimes that do not offer it. Express capability intent with `metadata.model_tier:` instead, resolved through `config/model-tiers.yaml`. See [Model Assignment Convention](../../skills/datarim-system/SKILL.md).

## Consilium Panels

Agents can be assembled into panels for multi-perspective analysis:

- **Architecture panel:** architect + strategist + security + sre + devops
- **Code panel:** developer + reviewer + code-simplifier
- **Production panel:** sre + devops + security
- **Feature panel:** strategist + architect + developer + writer
- **Content panel:** writer + editor
- **Knowledge panel:** librarian + architect + writer
- **Custom:** any 3-7 agents based on the question

See `skills/consilium/SKILL.md` for the full panel discussion protocol.
