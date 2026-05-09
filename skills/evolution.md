---
name: evolution
description: Rules for proposing and applying framework improvements. Covers growth (new components) and maintenance (pruning, merging). Human approval required.
model: opus
runtime: [claude, codex]
current_aal: 2
target_aal: 3
---

# Evolution — Framework Self-Update and Optimization Rules

## What is Evolution

Datarim improves itself in two ways:

1. **Growth** — after each completed task, the `reflecting` skill (invoked by `/dr-archive` Step 0.5) analyzes lessons learned and proposes targeted improvements: new skills, updated agents, expanded templates.
2. **Maintenance** — periodically or on demand, `/dr-optimize` audits the framework for bloat, duplicates, broken references, and inefficiencies, then proposes cleanup and consolidation.

Both paths require **explicit human approval** for every change. Evolution is how Datarim avoids repeating mistakes, accumulates institutional knowledge, and stays lean over time.

---

## When Triggered

### Automatic: Inside `/dr-archive` Step 0.5 via `reflecting` skill (Growth)

The agent:
1. Reviews the reflection document just created
2. Identifies patterns that could benefit future tasks
3. Generates zero or more Evolution Proposals
4. **Bloat check**: Counts total skills, agents, commands. If any threshold is exceeded (see Health Metrics below), suggests running `/dr-optimize`
5. Presents proposals to the human for approval
6. Applies only approved changes

### Explicit: Via `/dr-optimize` (Maintenance)

The optimizer agent:
1. Performs a full audit of all framework components
2. Builds a dependency graph (commands → agents → skills)
3. Detects unused, oversized, duplicate, and broken components
4. Generates optimization proposals
5. Presents report and proposals for approval
6. Applies approved changes and syncs all documentation

### User-requested: Via `/dr-addskill` (Growth)

When creating new components, the skill-creator agent:
1. Audits existing framework before creating anything new
2. Prefers updating existing components over creating new ones
3. Follows the Anti-Bloat Rule (below)

**No automatic modifications.** Every change requires explicit human approval across all paths.

> **Historical note (v1.10.0):** the standalone `/dr-reflect` command was retired and consolidated into `/dr-archive` Step 0.5 via the `reflecting` skill — reflection must run on every archive, not optionally. Disaster-recovery procedures for runtime files live in `skills/utilities/recovery.md` (cross-referenced from `skills/evolution/disaster-recovery.md`).

---

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `skills/evolution/class-ab-gate.md`
  Use when evaluating whether a proposal changes the framework contract (Class A vs B operating-model gate, founding incident, decision aid, atomicity rule).
- `skills/evolution/disaster-recovery.md`
  Use when runtime files in `$HOME/.claude/` are lost or corrupted. 5-channel recovery checklist.
- `skills/evolution/examples-and-patterns.md`
  Use for reference when writing proposals or applying the deprecation pattern (forward-pointer annotations).
- `skills/evolution/stack-agnostic-gate.md`
  MANDATORY pre-apply check before writing any approved Class A proposal to runtime. Rejects stack-specific content; whitelists `tech-stack.md` and the gate skill itself. CI helper at `scripts/stack-agnostic-gate.sh`.

---

## Proposal Categories

### Growth Categories (from `/dr-archive` Step 0.5 reflection)

| Category | Target | Description |
|----------|--------|-------------|
| `skill-update` | `skills/{name}.md` | Improve existing skill — add recipes, fix inaccuracies, expand coverage |
| `agent-update` | `agents/{name}.md` | Refine agent capabilities, context loading, or decision criteria |
| `claude-md-update` | `CLAUDE.md` | Update project-level rules, pipeline definitions, or conventions |
| `new-template` | `templates/{name}.md` | Create template for a recurring pattern |
| `new-skill` | `skills/{name}.md` | Create entirely new skill for an uncovered domain |

### Optimization Categories (from `/dr-optimize`)

| Category | Target | Description |
|----------|--------|-------------|
| `prune-skill` | `skills/{name}.md` | Remove an unused or obsolete skill |
| `prune-agent` | `agents/{name}.md` | Remove an unused or obsolete agent |
| `prune-command` | `commands/{name}.md` | Remove an unused or obsolete command |
| `merge-skills` | `skills/{name}.md` | Combine two overlapping skills into one |
| `merge-agents` | `agents/{name}.md` | Combine two overlapping agents into one |
| `split-skill` | `skills/{name}.md` | Split an oversized skill into base + supporting files |
| `rewrite-skill` | `skills/{name}.md` | Restructure a skill for clarity and context efficiency |
| `fix-description` | any `.md` | Optimize description for better auto-triggering or shorter context |
| `fix-references` | any `.md` | Fix broken cross-references between components |
| `sync-docs` | `CLAUDE.md`, `README.md`, `dr-help.md` | Update documentation counts and tables to match actual files |

---

## Proposal Format

Each proposal is a self-contained block.

```markdown
## Evolution Proposal

- **Category:** skill-update
- **Target:** skills/testing.md
- **What:** Add property-based testing section with hypothesis/fast-check examples
- **Why:** Discovered during a prior incident that property tests caught edge cases unit tests missed.
- **Impact:** Medium — affects testing strategy for all future tasks
- **Risk:** Low / Medium / High
- **Diff preview:**
  ```
  + ## Property-Based Testing
  + When to use: data transformation, serialization, parsers, math operations.
  ```
```

### Required Fields

| Field | Description |
|-------|-------------|
| **Category** | One of the categories above (growth or optimization) |
| **Target** | File path relative to the framework root |
| **What** | Concise description of the change (one sentence) |
| **Why** | Evidence — from task reflection, audit findings, or user request |
| **Impact** | Low / Medium / High — how broadly this affects future tasks |

### Optional Fields

| Field | Description |
|-------|-------------|
| **Risk** | Low / Medium / High — how likely this is to break something |
| **Diff preview** | Approximate content to add/change |
| **Alternatives** | Other approaches considered |
| **Depends on** | Other proposals that must be applied first |

---

## Human Approval Gate

After presenting proposals, the agent MUST:

1. List all proposals with their number, category, target, risk, and one-line summary
2. Ask: "Which proposals should I apply? (all / none / comma-separated numbers)"
3. Wait for explicit response
4. Apply ONLY the approved proposals
5. Skip or discard rejected proposals without argument

**Never apply changes speculatively.** Never say "I'll go ahead and update this" without approval.

---

## Health Metrics

These thresholds trigger an optimization suggestion during `/dr-archive` Step 0.5 (reflecting skill):

| Metric | Threshold | Action |
|--------|-----------|--------|
| Total skills | >20 | Suggest `/dr-optimize` — check for merges |
| Total agents | >18 | Suggest `/dr-optimize` — check for merges |
| Total commands | >25 | Suggest `/dr-optimize` — check for duplicates |
| Any skill >500 lines | — | Suggest splitting into base + supporting files |
| Total description chars | >8000 | Suggest shortening descriptions |
| Any description >155 chars | — | Shorten to ≤155 chars (sufficient for discovery) |
| Orphan rate | >15% components unreferenced | Suggest `/dr-optimize` — prune orphans |

The optimizer reports these metrics in its audit. Healthy frameworks stay under all thresholds.

**Audit persistence:** When running `/dr-optimize`, write the structured report to `datarim/reports/optimize-audit-{YYYY-MM-DD}.md` for historical tracking. Chat-only findings are lost on context compaction.

---

## Anti-Bloat Rule

**Prefer updating existing files over creating new ones.**

Before proposing `new-skill`, `new-template`, or any new file:
1. Check if an existing skill could absorb the content
2. Check if an existing template could be extended
3. Only create a new file if the content is clearly a distinct concern

Before proposing a merge:
1. Verify both components serve the same domain
2. Check that no information is lost in the merge
3. Update all cross-references after merging

Framework bloat degrades agent performance. Every new file adds to context loading overhead. Every description adds to the context budget. Keep the framework as small as it needs to be and no smaller.

---

## Evolution Log

All approved changes are logged in `datarim/docs/evolution-log.md`. Create this file if it does not exist.

### Log Format

```markdown
# Evolution Log

| Date | Task ID | Category | Target | Change | Rationale |
|------|---------|----------|--------|--------|-----------|
| 2026-04-11 | OPT-001 | prune-skill | skills/old-unused.md | Removed unused skill | No agent references it |
```

For optimization runs, use `OPT-NNN` as the task ID. For growth proposals from `/dr-archive` Step 0.5 reflection, use the current task ID.

---

## Rollback

Each Evolution change is a discrete edit to a specific file. Rollback strategy:

- **If using git:** Each approved set of changes should be a single commit with a message referencing the task ID. Revert via `git revert`.
- **If not using git:** The evolution log provides enough information to manually undo changes. The diff preview in the original proposal shows what was added.
- **For prune operations:** The optimizer creates a backup of deleted files in `documentation/archive/optimized/` before removal. Files can be restored from there.

> **Note:** Since 2026-04-22, `skills/`, `commands/`, `agents/`, `templates/` in `$HOME/.claude/` are symlinks to the Datarim git repo. Manual sync (`install.sh`) is no longer needed for these directories — changes are shared instantly. `install.sh` remains relevant only for first-time installation or rollback. See `skills/datarim-system/path-and-storage.md` § Symlink Architecture.

**Rule:** Never make changes that cannot be independently reverted. If two proposals modify the same file, apply them as separate edits so either can be rolled back without affecting the other.

---

## Pattern: Split-Architecture Metrics for Absorption Tasks

When a Class B task absorbs new components (skills, templates, fragments) into a **cold path** — meaning the new files are loaded on-demand at invocation time, not auto-loaded into every session — an aggregate token-budget metric (`total_chars_after / total_chars_before ≤ N%`) becomes meaningless because the hot path never sees the cold-path mass. Aggregate gates fail by design under structural absorption.

**Rule:** any absorption task whose plan adds files that are not auto-loaded MUST replace the aggregate metric with a split-axis metric:

1. **Idle hot-path budget** — measure only the entry skills/files loaded by every pipeline command (the discovery skill, system contract, mandatory loaders). Tight bound here protects per-invocation token cost.
2. **Per-existing-file delta** — bound the per-file growth on any file that existed in the baseline (e.g. `≤+30% chars`). Catches in-place bloat of touched components.
3. **On-demand exempt** — newly introduced files loaded only on invocation are reported informationally (count, total chars) but excluded from the gate.

**Why it matters:** absorbing N new on-demand skills inflates aggregate chars by Σ(new) regardless of runtime cost. A single aggregate gate forces a false trade-off between absorption and «no growth»; a split-axis gate aligns the metric with how runtime actually loads content.

**Falsifiability requirement:** each axis MUST have a concrete measurement command in `dev-tools/` that returns exit 0 (PASS) / exit 1 (FAIL). PRD AC text references the command directly so QA and Compliance re-runs are deterministic.

**Source:** Datarim v2.0.0 absorption (14 skills + 4 templates) — original aggregate ≤+10% gate violated by +27% structural addition; reformulated mid-task into hot-path ≤+16% + per-file ≤+30% + on-demand exempt.

---

## Pattern: Memory Rule → Executable Gate at Apply Step

When a user-memory rule (e.g. `~/.claude/projects/<proj>/memory/feedback_*.md`) repeatedly surfaces in reflection as a corrective action — meaning the rule was declared, then violated, then manually reverted — text-only memory is no longer sufficient at scale. Promote the rule to an **executable gate at the apply step** of the relevant pipeline command.

**Trigger threshold:** N ≥ 2 occurrences of the same memory rule appearing as a reflection corrective in distinct tasks within a short window (≤14 days).

**Gate anatomy:**

1. **Runtime contract** — `skills/<area>/<rule-name>-gate.md` documenting trigger, scope, allow/deny criteria, escape hatches, decision matrix. Markdown checklist agents can apply via Read+grep when no script is reachable.
2. **CI helper** — `scripts/<rule-name>-gate.sh` (pure bash, dependency-free). Same logic, scriptable for bats and CI. Exit codes: `0` PASS / `1` FAIL / `2` invocation error.
3. **Hooks** — embed «MUST run gate» line in every command/skill that reaches the apply step the rule should guard. Failure to embed = silently disabled gate.
4. **Bats fixtures** — at minimum 1 FAIL fixture (golden violation reproducing the original incident) + 1 PASS fixture (legitimate negative case) + 1 regression-invariant test on the gate's own host file (catches re-introduction of the violation).
5. **Whitelist + escape hatch** — declare any file that is exempt by design (e.g. `tech-stack.md` for stack-keywords). Provide a per-block escape marker (e.g. HTML-comment fence) for legitimate illustrative content. Use sparingly; reviewers should challenge each usage.

**Source incident:** `feedback_datarim_stack_agnostic.md` declared 2026-04-25, violated the next day across three artefacts. Memory rule advisory; gate enforces.

**Reuse candidates:** consider this pattern for any future recurring memory rule — e.g. «no-secrets-in-code», «no-personal-paths», «no-deprecated-API-XXX», ecosystem-specific keyword bans.