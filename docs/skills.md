# Skills Reference

Datarim includes 21 reusable skill modules. Skills provide rules, patterns, and guidelines loaded on demand by agents and commands.

Skills are split into two categories:
- **Reference skills** — rules and patterns the caller applies inline. Inherit caller's model (no `model` field).
- **Task skills** — perform an action when invoked. Have explicit `model` field per [Model Assignment Convention](../skills/datarim-system.md).

## Skill Catalog

| Skill | Type | Model | Purpose | Loaded By |
|-------|------|-------|---------|-----------|
| datarim-system | Reference | inherit | Core workflow rules, path resolution, file locations | All commands (mandatory) |
| ai-quality | Reference | inherit | 5 pillars: decomposition, TDD, architecture-first, focus, context | developer, planner |
| security | Reference | inherit | Auth, input validation, data protection | reviewer, security agent |
| testing | Reference | inherit | Testing pyramid, frameworks, mocking rules | developer, reviewer |
| performance | Reference | inherit | Lazy loading, caching, batching, DB optimization | architect, sre |
| tech-stack | Reference | inherit | Stack selection by project type | planner, architect |
| consilium | Task | opus | Multi-agent panel discussions | /dr-design (L3-4) |
| evolution | Task | opus | Framework self-update rules | /dr-reflect |
| incident-investigation | Task | opus | Root cause analysis for incidents | sre, on demand |
| compliance | Task | sonnet | 7-step post-QA hardening workflow | compliance agent |
| discovery | Task | sonnet | Requirements discovery interview | /dr-prd |
| dream | Task | sonnet | Knowledge base maintenance rules | librarian |
| factcheck | Task | sonnet | Fact verification for publications | editor, on demand |
| humanize | Task | sonnet | AI text pattern removal | editor, on demand |
| marketing | Task | sonnet | Ad campaigns, conversion tracking, growth | on demand |
| seo-launch | Task | sonnet | SEO, analytics, website/app launch checklists | on demand |
| visual-maps | Task | sonnet | Mermaid workflow diagrams | on demand |
| writing | Task | sonnet | Content creation and editorial workflow | writer, editor |
| remote-measurement | Task | haiku | Efficient remote host iteration (upload-run-stream pattern) | on demand (≥50-item SSH loops) |
| telegram-publishing | Task | haiku | Telegram Bot API publishing | on demand |
| utilities | Task | haiku | Native shell recipes for common operations | Any agent (on demand) |

**Distribution:** 6 reference (inherit), 3 opus, 9 sonnet, 3 haiku.

## Loading Hierarchy

1. **Always loaded:** `datarim-system.md` (by every command)
2. **Per-stage:** Skills specified in agent's Context Loading section
3. **On demand:** Specialized skills loaded when the task requires them

## Skill File Format

**Reference skill** (no `model` field — inherits from caller):

```markdown
---
name: {skill-name}
description: {one-line description}
---

# {Skill Title}

(Rules, patterns, guidelines, templates — applied inline by caller)
```

**Task skill** (explicit `model` — required):

```markdown
---
name: {skill-name}
description: {one-line description}
model: sonnet  # or opus / haiku per Model Assignment Convention
---

# {Skill Title}

(Step-by-step instructions, checklists, workflows — performs an action when invoked)
```

See [Model Assignment Convention](../skills/datarim-system.md) in `datarim-system.md` for choosing the right model.
