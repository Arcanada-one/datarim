---
name: evolution
description: Rules for proposing, applying, and optimizing framework improvements. Covers growth (new components via /dr-archive Step 0.5 reflecting skill) and maintenance (pruning, merging, efficiency via /dr-optimize). Human approval required for all changes.
model: opus
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

## Class A vs Class B — Operating-Model Gate

Not all proposals are equivalent at the approval step. Reflection approval is sufficient for *content* changes, but framework *contract* changes require a PRD update first. The gate below codifies this distinction after the TUNE-0002 → TUNE-0003 incident.

### Class A — Content changes (reflection approval sufficient)

Proposals that add, refine, or clarify the content of existing skills, agents, commands, or templates — without changing the framework's contract with its users.

Examples of Class A:
- Add a new recipe to `utilities.md`
- Restore a missing section to `testing.md`
- Tighten a classification list in `dr-do.md` (e.g. review-feedback categories)
- Promote a runtime-only skill into the repo
- Add a new `*.md` template for a recurring pattern
- Fix a cross-reference or typo

**Approval path:** `/dr-archive` Step 0.5 (reflecting skill) → user approval → apply to runtime → curate to repo. Normal flow.

### Class B — Operating-model changes (PRD update required BEFORE approval)

Proposals that change the framework's contract — how it is understood, installed, synced, or orchestrated. These are NOT just content edits; they alter what Datarim *is* for projects that use it.

Class B triggers (non-exhaustive):

- **Source-of-truth direction:** "Make repo canonical," "Make runtime canonical," "Switch to X-first model"
- **Sync semantics:** Change how `install.sh` handles existing files, redefine drift interpretation, change curation policy (who approves what)
- **Pipeline routing:** Reorder pipeline stages, change complexity-level → pipeline mapping, add/remove a mandatory gate
- **Core contract:** Redefine task ID invariance rules, change archive-area mapping contract, alter path resolution rules, change PRD waiver policy at the class level (not a single waiver, the policy itself)
- **Command semantics:** Change what a command *means* (not just how it executes), e.g. making `/dr-archive` optional instead of gating

**Approval path for Class B:**

1. Reflection generates the proposal and flags it as Class B in the proposal block.
2. `/dr-archive` Step 0.5 (reflecting skill) pauses — does NOT ask for proposal approval yet; also does NOT proceed to Step 1.
3. Instead, asks the user: "This proposal changes operating model. Update `PRD-datarim-sdlc-framework.md` first? Draft the PRD diff before approval?"
4. User either drafts PRD change (or approves a draft) — PRD becomes the source-of-truth for the new contract.
5. Only AFTER PRD is updated does the proposal re-enter normal Class A approval flow.
6. Implementation of the proposal must cite the PRD section that authorizes it.

### Founding incident (2026-04-15..16)

TUNE-0002 research concluded "repo-first operating model should replace runtime-first" based on research-level reasoning. This was treated as a regular proposal and approved through the normal reflection gate. TUNE-0003 then executed it — bumping VERSION, rewriting README Operating Model section, rewriting wrapper CLAUDE.md to 5-step repo-first workflow — without reconciling against `PRD-datarim-sdlc-framework.md`, which explicitly specified runtime-first via `/dr-reflect` (the command existing at the time of the incident; consolidated into `/dr-archive` Step 0.5 in v1.10.0 via TUNE-0013).

The PRD was the load-bearing contract. The reflection gate had no way to see that. Result:

1. Wrong-direction docs committed as v1.7.0.
2. `install.sh --force` run during /dr-archive on the (now stale-again) runtime, overwriting 9 files with repo content that had been built on the wrong premise.
3. Mid-task correction to runtime-first (v1.8.0), 4 hours of recovery + 4 files of TUNE-0011 reconstruction work downstream.

**Lesson:** research conclusions cannot silently override PRDs. The PRD is the contract; research proposes, PRD ratifies.

### How to tell if a proposal is Class B (decision aid)

Ask three questions. If the answer to any is YES, treat as Class B:

1. **Does this change affect users of the framework beyond this project?** (e.g. it would appear in installer-onboarding docs, getting-started guide, or README)
2. **Is the current behavior documented in `PRD-datarim-sdlc-framework.md`?** (if yes, changing it requires updating the PRD)
3. **Could two reasonable people reading the proposal disagree on what the framework promises after the change?** (if yes, you need a PRD to arbitrate)

If all three are NO — Class A, proceed normally.

### Why this gate is worth the friction

PRD updates add ~15-30 minutes of work per Class B proposal. The TUNE-0002 → TUNE-0003 incident cost ~6 hours of wrong-direction implementation + correction + TUNE-0011 recovery, or ~12x the gate cost. The gate also creates a persistent record (PRD diff + rationale) that future research can reconcile against instead of re-deriving.

### Projects without a framework-level PRD

Datarim framework itself has `PRD-datarim-sdlc-framework.md` as the contract artifact. But consumer projects that use Datarim as an installed framework often do not have their own framework-level PRD. The Class B gate still applies — it just points at a different contract artifact.

For consumer projects, PRD substitutes in priority order:

1. **Project-level PRD** at `datarim/prd/PRD-{project-id}.md` — if the project has one covering the area the proposal touches, update it.
2. **Project `CLAUDE.md`** — the top-level project contract. Changes to source-of-truth direction, sync semantics, or core conventions must update `CLAUDE.md` with the new rule and a rationale comment.
3. **Architectural decision records** (`datarim/creative/*.md` or project's ADR directory) — if the change reflects a design decision, record it there with "supersedes ADR-N" linkage.
4. **None of the above** — then the proposal is really a framework-level Class B change disguised as a project-level one. Escalate to Datarim framework PRD update (`PRD-datarim-sdlc-framework.md`) instead of inlining into the project.

**Rule:** a Class B proposal always needs a written contract artifact that ratifies it. Never apply a Class B change whose only justification is a reflection entry. Reflection proposes; a contract ratifies.

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

For optimization runs, use `OPT-NNN` as the task ID. For growth proposals from `/dr-archive` Step 0.5 reflection, use the current task ID.

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

### Growth (from /dr-archive Step 0.5 reflection)

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

---

## Deprecation Pattern: Forward-Pointer Annotation + Sweep Whitelist

When a concept, command, or convention is removed or renamed, historical references to it inevitably remain in changelog entries, incident narratives, and archived task documents. Rather than rewriting history, use **forward-pointer annotations** — explicit notes that point the reader from the old name to the current one.

### Pattern

1. **Delete/rename** the live artifact (e.g. remove `commands/dr-reflect.md`).
2. **Sweep** all live spec/doc/agent/skill/command files — replace operational references with the new name.
3. **Preserve** historical mentions (changelogs, incident narratives, archived reflections) with a **forward-pointer annotation** on each, citing the version and task ID: `"(consolidated into /dr-archive Step 0.5 in v1.10.0 via TUNE-0013)"`.
4. **Create a bats sweep-test** (T3-style) that:
   - Lists every file matching the old term via `grep -rln`.
   - Checks each against an explicit **whitelist** (files allowed to mention the old term).
   - Verifies each whitelisted file also contains the version/task-ID forward-pointer.
   - Fails with a diagnostic if any non-whitelisted file matches.
5. **Record the whitelist** in the test file header with rationale for each entry.

### Why

- History is preserved: future readers can trace *what was → what is* without external docs.
- Accidental re-introduction is caught by the sweep-test (any new file mentioning the old term fails T3a).
- Whitelisted files are self-documenting (the annotation is in the same line as the old term).
- The pattern is composable: each deprecation adds its own sweep-test; they don't conflict.

### Exemplar

TUNE-0013 (v1.10.0): removal of `/dr-reflect` command. Whitelist: `CLAUDE.md`, `docs/pipeline.md`, `commands/dr-archive.md`, `skills/reflecting.md`, `skills/evolution.md`. Sweep-test: `tests/reflect-removal-sweep.bats` (4 assertions: T3a whitelist, T3b forward-pointer, T3c file-deleted, T3d visual-maps clean).
