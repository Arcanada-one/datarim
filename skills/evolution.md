---
name: evolution
description: Rules for proposing and applying framework improvements during /dr-reflect. Human approval required for all changes.
---

# Evolution — Framework Self-Update Rules

## What is Evolution

Datarim improves itself based on lessons learned from each completed task. After every `/dr-reflect`, the agent analyzes insights from the task and proposes targeted improvements to the framework — skills, agents, templates, or project configuration.

Evolution is how Datarim avoids repeating mistakes and accumulates institutional knowledge.

---

## When Triggered

Evolution runs as the final step of `/dr-reflect`. The agent:

1. Reviews the reflection document just created
2. Identifies patterns that could benefit future tasks
3. Generates zero or more Evolution Proposals
4. Presents proposals to the human for approval
5. Applies only approved changes

**No automatic modifications.** Every change requires explicit human approval.

---

## Proposal Categories

| Category | Target | Description |
|----------|--------|-------------|
| `skill-update` | `skills/{name}.md` | Improve existing skill content — add missing recipes, fix inaccuracies, expand coverage |
| `agent-update` | `agents/{name}.md` | Refine agent capabilities, context loading, or decision criteria |
| `claude-md-update` | `CLAUDE.md` | Update project-level rules, pipeline definitions, or conventions |
| `new-template` | `templates/{name}.md` | Create new template based on a recurring pattern discovered during the task |
| `new-skill` | `skills/{name}.md` | Propose an entirely new skill when existing skills don't cover a discovered need |

---

## Proposal Format

Each proposal is a self-contained block presented in the reflection output.

```markdown
## Evolution Proposal

- **Category:** skill-update
- **Target:** skills/testing.md
- **What:** Add property-based testing section with hypothesis/fast-check examples
- **Why:** Discovered during TASK-0042 that property tests caught edge cases unit tests missed. Three bugs found by property tests were not covered by example-based tests.
- **Impact:** Medium — affects testing strategy for all future tasks
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
| **Category** | One of the five categories above |
| **Target** | Exact file path relative to the framework root |
| **What** | Concise description of the change (one sentence) |
| **Why** | Evidence from the current task that justifies the change |
| **Impact** | Low / Medium / High — how broadly this affects future tasks |

### Optional Fields

| Field | Description |
|-------|-------------|
| **Diff preview** | Approximate content to add/change (helps human evaluate) |
| **Alternatives** | Other approaches considered and why this one was chosen |

---

## Human Approval Gate

After presenting proposals, the agent MUST:

1. List all proposals with their category, target, and one-line summary
2. Ask: "Which proposals should I apply? (all / none / comma-separated numbers)"
3. Wait for explicit response
4. Apply ONLY the approved proposals
5. Skip or discard rejected proposals without argument

**Never apply changes speculatively.** Never say "I'll go ahead and update this" without approval.

---

## Evolution Log

All approved changes are logged in `datarim/docs/evolution-log.md`. Create this file if it does not exist.

### Log Format

```markdown
# Evolution Log

| Date | Task ID | Category | Target | Change | Rationale |
|------|---------|----------|--------|--------|-----------|
| 2026-04-08 | TASK-0042 | skill-update | skills/testing.md | Added property-based testing section | Property tests caught 3 edge cases missed by unit tests |
| 2026-04-05 | TASK-0038 | new-template | templates/api-endpoint.md | Created API endpoint template | Same boilerplate written in 4 consecutive tasks |
```

Each row captures enough context to understand why the change was made without reading the full reflection.

---

## Anti-Bloat Rule

**Prefer updating existing files over creating new ones.**

Before proposing `new-skill` or `new-template`:
1. Check if an existing skill could absorb the content
2. Check if an existing template could be extended
3. Only propose a new file if the content is clearly a distinct concern

Framework bloat degrades agent performance. Every new file adds to context loading overhead.

---

## Rollback

Each Evolution change is a discrete edit to a specific file. Rollback strategy:

- **If using git:** Each approved set of changes should be a single commit with a message referencing the task ID. Revert via `git revert`.
- **If not using git:** The evolution log provides enough information to manually undo changes. The diff preview in the original proposal shows what was added.

**Rule:** Never make changes that cannot be independently reverted. If two proposals modify the same file, apply them as separate edits so either can be rolled back without affecting the other.

---

## Examples of Good Proposals

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

**Bad — vague, no evidence:**
```
Category: skill-update
Target: skills/ai-quality.md
What: Make it better
Why: Felt incomplete
Impact: Low
```

**Bad — bloat, could be part of existing skill:**
```
Category: new-skill
Target: skills/error-handling.md
What: Error handling patterns
Why: Would be useful
→ Should be a section in skills/ai-quality.md or skills/testing.md instead
```
