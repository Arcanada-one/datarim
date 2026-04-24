---
name: evolution/examples-and-patterns
description: Good/bad evolution proposal examples and deprecation pattern. Reference for writing quality proposals.
---

# Evolution Examples and Patterns

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