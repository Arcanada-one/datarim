---
name: evolution
description: Rules for proposing, applying, and optimizing framework improvements. Covers growth (new components via /dr-reflect) and maintenance (pruning, merging, efficiency via /dr-optimize). Human approval required for all changes.
model: opus
---

# Evolution — Framework Self-Update and Optimization Rules

## What is Evolution

Datarim improves itself in two ways:

1. **Growth** — after each completed task, `/dr-reflect` analyzes lessons learned and proposes targeted improvements: new skills, updated agents, expanded templates.
2. **Maintenance** — periodically or on demand, `/dr-optimize` audits the framework for bloat, duplicates, broken references, and inefficiencies, then proposes cleanup and consolidation.

Both paths require **explicit human approval** for every change. Evolution is how Datarim avoids repeating mistakes, accumulates institutional knowledge, and stays lean over time.

---

## When Triggered

### Automatic: After `/dr-reflect` (Growth)

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

---

## Proposal Categories

### Growth Categories (from `/dr-reflect`)

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
- **Why:** Discovered during TASK-0042 that property tests caught edge cases unit tests missed. Three bugs found by property tests were not covered by example-based tests.
- **Impact:** Medium — affects testing strategy for all future tasks
- **Risk:** Low / Medium / High
- **Diff preview:**
  ```
  + ## Property-Based Testing
  + When to use: data transformation, serialization, parsers, math operations.
  + ...
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

These thresholds trigger an optimization suggestion during `/dr-reflect`:

| Metric | Threshold | Action |
|--------|-----------|--------|
| Total skills | >20 | Suggest `/dr-optimize` — check for merges |
| Total agents | >18 | Suggest `/dr-optimize` — check for merges |
| Total commands | >25 | Suggest `/dr-optimize` — check for duplicates |
| Any skill >500 lines | — | Suggest splitting into base + supporting files |
| Total description chars | >8000 | Suggest shortening descriptions |
| Orphan rate | >15% components unreferenced | Suggest `/dr-optimize` — prune orphans |

The optimizer reports these metrics in its audit. Healthy frameworks stay under all thresholds.

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
| 2026-04-11 | OPT-001 | prune-skill | skills/old-unused.md | Removed unused skill | No agent references it, no invocation in 30+ tasks |
| 2026-04-11 | OPT-001 | merge-skills | skills/testing.md | Merged testing-helpers.md into testing.md | 80% overlap, single skill is clearer |
| 2026-04-08 | TASK-0042 | skill-update | skills/testing.md | Added property-based testing section | Property tests caught 3 edge cases missed by unit tests |
```

For optimization runs, use `OPT-NNN` as the task ID. For growth proposals from `/dr-reflect`, use the current task ID.

---

## Disaster Recovery for Lost Runtime Files

When runtime files in `$HOME/.claude/` are lost or corrupted (overwrite, accidental `install.sh --force`, deletion), do NOT declare them "unrecoverable" until the following checklist has been run. TUNE-0011 recovered 4 files that TUNE-0003 archive had declared impossible to reconstruct — the difference was exhaustive source discovery.

### Recovery Checklist (apply in order, ~5 minutes per channel)

1. **Grep all reflection docs by filename** — not just reflections of the "obvious parent" task. Search every `datarim/reflection/*.md` across all projects in the incident window for any mention of the lost filename. A reflection from an unrelated task may have proposed changes to the file (as WEB-0002 P4 did for `tester.md`).
2. **Check compacted session contexts** — if the incident happened in a session where the lost skill/command was previously invoked via the Skill tool, its content is preserved in the session's system-reminder blocks and survives `/compact`. See `skills/utilities.md § Recovering Runtime Files from Compacted Session Context` for extraction recipe.
3. **Follow cross-references** — when file A documents that file B has section §X (e.g. `dr-qa.md` Layer 4d references `testing.md § Live Smoke-Test Gate`), the cross-reference is an implicit spec for B.§X even if B is lost. Reconstruct by synthesizing B.§X from A's description of it.
4. **Git history of consumer projects** — if the lost file is framework code used by multiple projects, commits in those projects during the incident window may reveal how the file was being used, implying its pre-incident structure.
5. **External backups — last resort only** — Time Machine, APFS snapshots, cloud sync, backup daemons. Check existence *before* relying on it; none may be present.

### Rule

**No "Known Loss" claim may be recorded without first running the 5-channel checklist.** If a channel yields content — recover, curate, move on. If all 5 are exhausted — only then declare loss, and record which channels were checked in the archive document (not just "not possible").

### Why this exists

TUNE-0003 archive claimed 4 files "text reconstruction not possible" after 0 minutes of discovery. TUNE-0011 recovered 100% of them in 20 minutes using channels 1-3. The cost of this checklist is ~25 minutes; the cost of a false "loss" claim is permanent content gap plus eroded trust in archive accuracy.

---

## Rollback

Each Evolution change is a discrete edit to a specific file. Rollback strategy:

- **If using git:** Each approved set of changes should be a single commit with a message referencing the task ID. Revert via `git revert`.
- **If not using git:** The evolution log provides enough information to manually undo changes. The diff preview in the original proposal shows what was added.
- **For prune operations:** The optimizer creates a backup of deleted files in `documentation/archive/optimized/` before removal. Files can be restored from there.

**Rule:** Never make changes that cannot be independently reverted. If two proposals modify the same file, apply them as separate edits so either can be rolled back without affecting the other.

---

## Examples of Good Proposals

### Growth (from /dr-reflect)

**Good — specific, evidence-based:**
```
Category: skill-update
Target: skills/security.md
What: Add rate limiting section with token bucket and sliding window patterns
Why: TASK-0051 required rate limiting on 3 endpoints; had to research patterns from scratch each time
Impact: Medium
```

**Good — new template justified by repetition:**
```
Category: new-template
Target: templates/migration-checklist.md
What: Checklist template for database migrations (backup, test, rollback plan, monitoring)
Why: Missed rollback plan in TASK-0047, causing 30min downtime. Same checklist needed in TASK-0044 and TASK-0039.
Impact: High
```

### Optimization (from /dr-optimize)

**Good — prune with evidence:**
```
Category: prune-skill
Target: skills/deprecated-helper.md
What: Remove deprecated helper skill
Why: Not referenced by any agent or command. Last used 40+ tasks ago. Functionality absorbed into utilities.md.
Impact: Low
Risk: Low
```

**Good — merge with clear rationale:**
```
Category: merge-skills
Target: skills/testing.md (absorb skills/test-helpers.md)
What: Merge test-helpers.md into testing.md
Why: 80% topic overlap. Both cover mocking patterns and test organization. Separate files cause confusion about where to look.
Impact: Medium
Risk: Medium — need to update 2 agent references
```

### Bad Proposals

**Bad — vague, no evidence:**
```
Category: skill-update
Target: skills/ai-quality.md
What: Make it better
Why: Felt incomplete
Impact: Low
```

**Bad — premature prune without checking references:**
```
Category: prune-agent
Target: agents/sre.md
What: Remove SRE agent
Why: Haven't used it recently
→ Must check: does any command or consilium panel reference it?
```
