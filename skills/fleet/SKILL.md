---
name: fleet
description: Router for fleet worker starter skills by task complexity tier (L1 basic to L5 autonomous). Load this entry first, then the single level fragment matching the task's complexity.
model: inherit
current_aal: 1
target_aal: 2
---

# Fleet — Complexity-Tier Worker Skills

Fleet workers receive a task brief plus one **complexity-tier** starter skill
that sets their context budget and operating rules. This entry is a router:
pick the single level fragment that matches the task's complexity, load it, and
follow it. Do not load more than one level.

## Choosing a level

| Level | When | Context budget | Fragment |
|-------|------|----------------|----------|
| L1 — basic | Single elementary step, one tool, no branching | ~200 tokens | `l1-basic/SKILL.md` |
| L2 — structured | A few templated steps, allowed-command list | ~500 tokens | `l2-structured/SKILL.md` |
| L3 — analyst | Analysis with a choice between alternatives; RAG on demand | ~1500 tokens | `l3-analyst/SKILL.md` |
| L4 — expert | Complex task with several subtasks; decompose and sequence | ~4000 tokens | `l4-expert/SKILL.md` |
| L5 — autonomous | Self-managed multi-subtask coordination; KB pre-fetch | ~6000 tokens | `l5-autonomous/SKILL.md` |

## Rules

- Load exactly one level fragment — the one matching the task's complexity.
- If a worker discovers the task exceeds its assigned level (e.g. an L1 task
  turns out to need analysis), it stops and reports `level-mismatch: needs >=Lx`
  instead of improvising above its tier.
- Higher levels widen the context budget and permitted operations; they never
  waive a role's `forbidden_actions` or any hard-gated action boundary.
