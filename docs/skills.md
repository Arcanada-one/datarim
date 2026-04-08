# Skills Reference

Datarim includes 13 reusable skill modules. Skills provide rules, patterns, and guidelines loaded on demand by agents and commands.

## Skill Catalog

| Skill | Purpose | Loaded By |
|-------|---------|-----------|
| datarim-system | Core workflow rules, path resolution, file locations | All commands (mandatory) |
| ai-quality | 5 pillars: decomposition, TDD, architecture-first, focus, context | developer, planner |
| compliance | 7-step post-QA hardening workflow | compliance agent |
| security | Auth, input validation, data protection | reviewer, security agent |
| testing | Testing pyramid, frameworks, mocking rules | developer, reviewer |
| performance | Lazy loading, caching, batching, DB optimization | architect, sre |
| tech-stack | Stack selection by project type (frontend, API, AI, real-time) | planner, architect |
| utilities | Native shell recipes for common operations | Any agent (on demand) |
| consilium | Multi-agent panel discussions | /dr-design (L3-4) |
| discovery | Requirements discovery interview | /dr-prd |
| evolution | Framework self-update rules | /dr-reflect |
| factcheck | Fact verification for publications | On demand |
| humanize | AI text pattern removal | On demand |

## Loading Hierarchy

1. **Always loaded:** `datarim-system.md` (by every command)
2. **Per-stage:** Skills specified in agent's Context Loading section
3. **On demand:** Specialized skills loaded when the task requires them

## Skill File Format

```markdown
---
name: {skill-name}
description: {one-line description}
---

# {Skill Title}

(Content: rules, patterns, guidelines, templates)
```
