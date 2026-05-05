# Commands Reference

Datarim provides 18 slash commands for Claude Code. Commands are grouped by category.

## Unified CTA Block (v1.16.0)

Every `/dr-*` command terminates its response with a canonical "Next Step" CTA block defined in `skills/cta-format.md`. The block contains:

1. The resolved task ID (so you always know which task this CTA applies to)
2. ≤5 numbered options (sweet spot: 3) — each with an exact command, task ID, and one-sentence purpose
3. Exactly one `**рекомендуется**` primary marker
4. `---` HR wrapping (top + bottom)
5. `**Другие активные задачи:**` Variant B menu when more than one task is active

Example:

```markdown
---

**Следующий шаг — TUNE-0032** (L3, in_progress)

1. `/dr-design TUNE-0032` — **рекомендуется** — auto-transition после plan для L3
2. `/dr-do TUNE-0032` — если creative-phase не нужен
3. `/dr-status` — backlog overview

**Другие активные задачи:**
- TUNE-0031 (L1) — `/dr-do TUNE-0031` — update.sh implementation

---
```

When `/dr-qa` returns BLOCKED or `/dr-compliance` returns NON-COMPLIANT, the CTA uses the FAIL-Routing variant: header changes to `**QA failed для {ID} — earliest failed layer: Layer N (Layer name)**` and the primary CTA points to the layer-return command (`/dr-prd`, `/dr-design`, `/dr-plan`, `/dr-do`).

Source: TUNE-0032. Spec: `skills/cta-format.md`. Template: `templates/cta-template.md`. Tests: `tests/cta-format.bats` (39 spec-regression tests + 3 fixtures).

## Pipeline Commands (8)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-init` | Initialize | planner | Create task, assess complexity, set up `datarim/`. Emits CTA. |
| `/dr-prd` | Requirements | architect | Generate PRD with discovery interview. Emits CTA. |
| `/dr-plan` | Planning | planner | Detailed implementation plan with strategist gate. Emits CTA. |
| `/dr-design` | Design | architect | Architecture exploration with consilium (L3-4). Emits CTA. |
| `/dr-do` | Execution | developer | TDD development, one method at a time. Emits CTA. |
| `/dr-qa` | Quality | reviewer | Multi-layer verification (PRD, design, plan, code). Emits CTA (FAIL-Routing variant on BLOCKED). |
| `/dr-compliance` | Hardening | compliance | 7-step post-QA hardening workflow. Emits CTA (FAIL-Routing variant on NON-COMPLIANT). |
| `/dr-archive` | Archive | reviewer (Step 0.5 reflection) + planner (Steps 1-7) | Reflection + evolution proposals + complete task + update backlog + reset context. Emits CTA. |

## Content Commands (3)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-write` | Content | writer | Create written content -- articles, docs, research, posts. Emits CTA. |
| `/dr-edit` | Content | editor | Editorial review -- fact-check, humanize, style, polish. Emits CTA. |
| `/dr-publish` | Content | writer | Adapt and publish content to multiple platforms. Emits CTA. |

## Framework Management (4)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-addskill` | Extension | skill-creator | Create or update skills, agents, commands with web research. Emits CTA. |
| `/dr-doctor` | Maintenance | -- | Diagnose and repair Datarim operational files — migrate to thin one-liner schema, externalize task descriptions, abolish progress.md. Emits CTA. |
| `/dr-dream` | Maintenance | librarian | Knowledge base maintenance: organize, lint, index, cross-reference. Emits CTA. |
| `/dr-optimize` | Maintenance | optimizer | Audit framework, prune unused, merge duplicates, sync docs. Emits CTA. |
| `/dr-plugin` | Extension | -- | Manage opt-in plugin system: list active plugins, enable/disable third-party modules. Phase A (TUNE-0101). Emits CTA. |

## Utility Commands (3)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-status` | Utility | -- | Check current task and backlog status (read-only). Emits CTA — discovery surface for parallel work. |
| `/dr-continue` | Utility | varies | Resume from last checkpoint. Emits CTA per resumed phase. |
| `/dr-help` | Utility | -- | List all commands with descriptions and usage guidance. Emits CTA. |

## Standalone Commands (2)

| Command | Agent | Description |
|---------|-------|-------------|
| `/factcheck` | -- | Fact-check articles and posts before publication |
| `/humanize` | -- | Remove AI writing patterns from text |

## Command File Format

```markdown
---
name: {command-name}
description: {one-line description}
---

# /{command} -- {Title}

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

# Write a blog post
/dr-write Create a blog post about our new API versioning strategy

# Editorial review of content
/dr-edit Review the blog post for publication readiness

# Add a new skill to the framework
/dr-addskill Create an accessibility skill covering WCAG 2.1 AA

# Audit and optimize the framework
/dr-optimize

# Organize and consolidate the knowledge base
/dr-dream
```
