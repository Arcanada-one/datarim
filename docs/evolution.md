# Self-Evolution

Datarim improves itself based on real project experience. This document explains how.

## How It Works

1. After completing a task, the `/dr-reflect` command analyzes what worked and what didn't
2. The agent proposes framework updates (new patterns, improved skills, refined agent behaviors)
3. **Human reviews and approves** each proposal — no automatic changes
4. Approved changes are applied and logged in `datarim/docs/evolution-log.md`

## What Can Evolve

| Category | Target | Example |
|----------|--------|---------|
| skill-update | Existing skill file | Add property-based testing section to testing.md |
| agent-update | Agent capabilities | Add GraphQL expertise to architect.md |
| claude-md-update | Project CLAUDE.md | Add new convention discovered during task |
| new-template | New template file | Create API migration checklist template |
| new-skill | New skill file | Create accessibility.md after a11y task |

## What Should NOT Evolve

- Core pipeline structure (init → ... → archive)
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

Prefer updating existing files over creating new ones. The framework should stay lean.

## Rollback

Every evolution change is a discrete file edit. Use git history to revert any change:
```bash
git log --oneline -- skills/testing.md
git checkout <commit> -- skills/testing.md
```
