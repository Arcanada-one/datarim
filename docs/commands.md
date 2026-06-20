# Commands Reference

Datarim provides 27 slash commands for Claude Code (plus 2 standalone /factcheck /humanize). Commands are grouped by category.

## Unified CTA Block (v1.16.0)

Every `/dr-*` command terminates its response with a canonical "Next Step" CTA block defined in `skills/cta-format/SKILL.md`. The block contains:

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

Source: TUNE-0032. Spec: `skills/cta-format/SKILL.md`. Template: `templates/cta-template.md`. Tests: `tests/cta-format.bats` (39 spec-regression tests + 3 fixtures).

## Pipeline Commands (8)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-init` | Initialize | planner | Create task, assess complexity, set up `datarim/`. Includes Step 2.5b — non-blocking topic-overlap advisory against pending backlog (v2.7.0+). Emits CTA. |
| `/dr-prd` | Requirements | architect | Generate PRD with discovery interview. Emits CTA. |
| `/dr-plan` | Planning | planner | Detailed implementation plan with strategist gate. Emits CTA. |
| `/dr-design` | Design | architect | Architecture exploration with consilium (L3-4). Emits CTA. |
| `/dr-do` | Execution | developer | TDD development, one method at a time. Emits CTA. |
| `/dr-qa` | Quality | reviewer | Multi-layer verification (PRD, design, plan, code). For deploy-class tasks, Layer 4g (Prod-Readiness Gate) runs a read-only test↔prod runner symmetry probe and blocks merge-proposal on FAIL/BLOCKED. Emits CTA (FAIL-Routing variant on BLOCKED). |
| `/dr-verify` | Verification | -- | Standalone tri-layer self-verification (on-demand). Layer 1 deterministic floor + Layer 2 cross-model peer-review (provider auto-resolves via 6-step chain — zero-flag UX, cross-Claude-family fallback when no external API key) + Layer 3 native runtime dispatch. Findings carry `source_layer` + `peer_review_mode` (`cross_vendor` / `cross_claude_family` / `same_model_isolated`); findings-only mode; emits CTA (FAIL-Routing variant on BLOCKED). |
| `/dr-spec` | Verification | -- | Spec-traceability façade (read-only). Validates the requirement graph `wish_id → D-REQ → V-AC → plan-step → evidence` via four `dev-tools/` validators (`dr-spec-lint`, `dr-trace`, `dr-lint`, `dr-spec-grade`) over one rule registry (`dr-spec-rules.yaml`). Common contract: `--format json`, exit `0/1/2`, mis-config = exit 2 never "0 violations". Advisory-first rollout; `dr-spec-grade` is a computed projection only (no routing). |
| `/dr-compliance` | Hardening | compliance | 7-step post-QA hardening workflow. Compliance report follows `templates/compliance-report-template.md` (v2.14.0+): four top sections in strict order — «Начальная задача», «Как решили», «Артефакты задачи», «Следующие шаги» — plus an audit addendum under `---` carrying `### Step-by-step verdicts`, `### Remaining risks`, `### Related`. Emits CTA (FAIL-Routing variant on NON-COMPLIANT). |
| `/dr-archive` | Archive | reviewer (Step 0.5 reflection) + planner (Steps 1-7) | Reflection + evolution proposals + complete task + update backlog + reset context. For deploy-class tasks, Step 0.4 (Prod-Merge Verification Gate) blocks archive until the production merge is done AND verified. Archive doc follows `templates/archive-template.md` (v2.14.0+): four top sections in strict order — «Начальная задача», «Как решили», «Артефакты задачи», «Следующие шаги» — plus an audit addendum under `---` carrying `### verification_outcome`, `### Acceptance Criteria`, `### Lessons Learned`, `### Operator Handoff`, `### Related`. The «Как решили» section is a single-level bullet list that maps each operator-brief bullet to a quoted item + Russian status word (выполнено / частично / не выполнено / неприменимо) + one or two plain-language sentences; expectations fold into the same list with marker «(уточнение брифа)». Emits CTA. |
| `/dr-auto` | Autonomous | orchestrator (spawns per-stage subagents) | Subagent orchestrator that drives a task from its current status to a passing `/dr-compliance` + reflection — it does NOT run the final `/dr-archive`. Spawns the matching agent per stage (planner/architect/developer/reviewer/compliance) via the Agent tool and summarises each result to decide the next stage. Activates `autonomous-mode.md` via env var `DATARIM_AUTO_MODE=1` + marker `datarim/.auto-mode-active`; the Question Suppression Ladder suppresses clarification questions; hard-gated actions still escalate to the operator. Stage-replay allowed. Two modes — Continue (`/dr-auto {TASK-ID}` resume) / Bootstrap (`/dr-auto "<free-text>"`). Emits CTA + stage snapshot `stage: auto`. |

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

## Utility Commands (5)

| Command | Stage | Agent | Description |
|---------|-------|-------|-------------|
| `/dr-status` | Utility | -- | Check current task and backlog status (read-only). Emits CTA — discovery surface for parallel work. |
| `/dr-next` | Utility | varies | Resume from last checkpoint. Step 2.5 reads `datarim/snapshots/{TASK-ID}.snapshot.md` first (v2.13.0+) and emits replay-prompt with bilingual autonomy reminder + `done before:` body. Falls back silently to legacy Read pipeline when snapshot is absent. Emits CTA per resumed phase. |
| `/dr-quick` | Utility | developer (lightweight) | Fast-lane for trivial fixes / quick lookups — assigns `QCK-XXXX`, weak-model KB scan, applies the change, writes a short `quick/` archive. Skips PRD / plan / design / QA / compliance. Emits CTA. |
| `/dr-save` | Utility | developer | Capture current session to `datarim/sessions/SESSION-{YYYYMMDD-HHMMSS}.session.md` before context is destroyed. 5-layer body (git state / active tasks / related files / open questions / failed approaches), 32 KB cap with non-truncatable L1/L5, append-only semantics, claim-provenance enforcement (exit 1 on untagged claims), T-8 secret redaction. Works identically in Claude Code, Codex CLI, and Cursor. Emits resume block. |
| `/dr-continue` | Utility | developer | Resume from session artefact written by `/dr-save` in a **clean context window**. Re-verifies every claim via live probes (STALE SNAPSHOT / CLAIM-UNVERIFIED / FILE-MISSING banners), downgrades provenance tags from the artefact, then routes to `/dr-next` or `/dr-auto`. Squash-collision detection via `git merge-base --is-ancestor`. |
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
/dr-next

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
