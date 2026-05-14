# Skills Reference

Datarim includes 45 reusable skill modules. Skills provide rules, patterns, and guidelines loaded on demand by agents and commands.

Skills are split into two categories:
- **Reference skills** — rules and patterns the caller applies inline. Inherit caller's model (no `model` field).
- **Task skills** — perform an action when invoked. Have explicit `model` field per [Model Assignment Convention](../skills/datarim-system.md).

## Skill Catalog

| Skill | Type | Model | Purpose | Loaded By |
|-------|------|-------|---------|-----------|
| datarim-system | Reference | inherit | Core workflow rules, path resolution, file locations | All commands (mandatory) |
| cta-format | Reference | inherit | Canonical CTA "Next Step" block format (v1.16.0, TUNE-0032) | planner, architect, developer, reviewer, compliance |
| ai-quality | Reference | inherit | 5 pillars: decomposition, TDD, architecture-first, focus, context | developer, planner |
| security | Reference | inherit | Auth, input validation, data protection | reviewer, security agent |
| testing | Reference | inherit | Testing pyramid, frameworks, mocking rules | developer, reviewer |
| performance | Reference | inherit | Lazy loading, caching, batching, DB optimization | architect, sre |
| tech-stack | Reference | inherit | Stack selection by project type | planner, architect |
| consilium | Task | opus | Multi-agent panel discussions | /dr-design (L3-4) |
| evolution | Task | opus | Framework self-update rules | /dr-archive (Step 0.5 via reflecting skill), /dr-optimize |
| reflecting | Task | inherit | Review-phase workflow: lessons learned, evolution proposals with Class A/B gate, health-metrics check, follow-up-task detection | /dr-archive (Step 0.5, internal only) |
| incident-investigation | Task | opus | Root cause analysis for incidents | sre, on demand |
| compliance | Task | sonnet | 7-step post-QA hardening workflow | compliance agent |
| discovery | Task | sonnet | Requirements discovery interview | /dr-prd |
| dream | Task | sonnet | Knowledge base maintenance rules | librarian |
| factcheck | Task | sonnet | Fact verification for publications | editor, on demand |
| humanize | Task | sonnet | AI text pattern removal | editor, on demand |
| go-to-market | Task | sonnet | SEO, analytics, ad campaigns, launch checklists | on demand |
| visual-maps | Task | sonnet | Mermaid workflow diagrams | on demand |
| writing | Task | sonnet | Content creation and editorial workflow | writer, editor |
| utilities | Task | haiku | Native shell recipes for common operations (12 fragment files) | Any agent (on demand) |
| datarim-doctor | Task | sonnet | /dr-doctor schema and migration semantics (thin one-liner contract) | /dr-doctor, /dr-init self-heal, /dr-archive line-format gate |
| file-sync-config | Reference | inherit | Pre-flight checklist + ignore patterns for file-sync (Syncthing/rclone) | on demand for sync setup |
| frontend-ui | Task | sonnet | CSS specificity, dark/light themes, visual testing, mobile responsiveness | when editing HTML/CSS |
| infra-automation | Task | sonnet | SSH batch execution, health checks, network debugging, pre-migration inventory | server ops tasks |
| project-init | Task | sonnet | Project scaffolding (CLAUDE.md, docs/, datarim/ structure) | /dr-init when project intent detected |
| publishing | Task | haiku | Multi-platform publishing rules, formatting, platform limits | writer, on demand |
| release-verify | Reference | inherit | Consumer-side release verification (sha256 → cosign verify-blob → gh attestation) | on install/update from GitHub Release |
| research-workflow | Task | sonnet | Structured external research methodology, checklist, tool selection | researcher agent in /dr-prd, /dr-do |
| security-baseline | Reference | inherit | Canonical S1–S9 security rule reference cited from CLAUDE.md § Security Mandate | plan/qa/compliance/do touching shipped artefacts |
| diataxis-docs | Reference | inherit | Documentation Taxonomy Mandate — 4 closed Diátaxis categories (tutorials / how-to / reference / explanation), mapping table, exemption list, anti-patterns | /dr-init project scaffolding, /dr-optimize audit, /dr-archive surface verification |
| init-task-persistence | Reference | inherit | Verbatim operator brief artefact contract — frontmatter + append-log + Q&A round-trip auto-append (v2.9.0); mandatory read by every pipeline command | All pipeline commands (mandatory READ at first step; six write Q&A blocks via `dev-tools/append-init-task-qa.sh`) |
| expectations-checklist | Reference | inherit | Operator wishlist artefact (Option B flat markdown) — wish_id slug + История статусов + Текущий статус + override semantics | /dr-prd, /dr-plan (write); /dr-qa, /dr-compliance (verify) |
| playwright-qa | Task | sonnet | Browser-based frontend QA — CLI / MCP / env-browser resolution chain + headed / headed-strict + per-task flock + run-`<ISO-ts>`/ artefacts | /dr-qa Layer 4f on frontend touch |
| human-summary | Reference | inherit | Plain-language operator recap — four sub-sections + banlist + whitelist + per-paragraph escape hatch + 150–400 word budget | /dr-qa, /dr-compliance, /dr-archive (Step 8) |

**Distribution:** 12 reference (inherit), 3 opus, 13 sonnet, 4 haiku.

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
