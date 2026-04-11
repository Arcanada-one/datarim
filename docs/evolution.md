# Self-Evolution

Datarim improves itself based on real project experience. This document explains how.

## How It Works

1. After completing a task, `/dr-reflect` analyzes what worked and what didn't
2. The agent proposes framework updates (new patterns, improved skills, refined agent behaviors)
3. **Human reviews and approves** each proposal -- no automatic changes
4. Approved changes are applied and logged in `datarim/docs/evolution-log.md`

## Growth Categories

| Category | Target | Example |
|----------|--------|---------|
| skill-update | Existing skill file | Add property-based testing section to testing.md |
| agent-update | Agent capabilities | Add GraphQL expertise to architect.md |
| claude-md-update | Project CLAUDE.md | Add new convention discovered during task |
| new-template | New template file | Create API migration checklist template |
| new-skill | New skill file | Create accessibility.md after a11y task |

## Optimization Categories

Used by `/dr-optimize` for framework maintenance:

| Category | Description |
|----------|-------------|
| prune-skill | Remove unused or redundant skill |
| prune-agent | Remove unused or redundant agent |
| merge-skills | Combine overlapping skills into one |
| merge-agents | Combine agents with overlapping roles |
| split-skill | Break an oversized skill into focused parts |
| rewrite-skill | Rewrite a skill for clarity or accuracy |
| fix-description | Correct agent/skill/command descriptions |
| fix-references | Fix broken file paths and cross-references |
| sync-docs | Update docs to match current agents, skills, commands |

## Health Metrics

The framework should stay lean. Run `/dr-optimize` when any threshold is exceeded:

| Metric | Threshold | Action |
|--------|-----------|--------|
| Skills | >20 | Audit for merges and prunes |
| Agents | >18 | Audit for overlapping roles |
| Commands | >25 | Audit for redundant commands |

## Maintenance Commands

- **`/dr-optimize`** -- Audit the framework itself: prune unused skills, merge duplicates, fix broken references, sync documentation. Run periodically or when the framework feels bloated.
- **`/dr-dream`** -- Maintain the knowledge base (`datarim/` directory): organize misplaced files, deduplicate content, cross-reference documents, archive stale content.

## What Should NOT Evolve

- Core pipeline structure (init -> ... -> archive)
- Path resolution rules
- Security controls
- Human approval requirement itself

## Evolution Log Format

`datarim/docs/evolution-log.md`:

```markdown
| Date | Task ID | Category | Target | Change | Rationale |
|------|---------|----------|--------|--------|-----------|
| 2026-04-09 | TASK-0001 | skill-update | testing.md | Added property-based testing | Caught 3 edge cases unit tests missed |
```

## Anti-Bloat Rule

Prefer updating existing files over creating new ones. The framework should stay lean. When in doubt, merge rather than create.

## Rollback

Every evolution change is a discrete file edit. Use git history to revert any change:
```bash
git log --oneline -- skills/testing.md
git checkout <commit> -- skills/testing.md
```
