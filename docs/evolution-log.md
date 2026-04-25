# Evolution Log

Append-only log of framework changes accepted from `/dr-archive` Step 0.5 reflection or curated runtime → repo updates.

---

## 2026-04-25 — v1.16.0 — TUNE-0032 — Canonical CTA "Next Step" Block

### Summary

Unified the "Next Step" Call-to-Action (CTA) emitted by every `/dr-*` command and pipeline agent. Before TUNE-0032, each command had ad-hoc free-form `## Next Steps` prose with no task ID, no primary marker, and no multi-task awareness — users running >1 parallel task could not tell which command applied to which task.

### Changes

**New files:**
- `skills/cta-format.md` — canonical spec (single source of truth)
- `templates/cta-template.md` — reusable Markdown snippet
- `tests/cta-format.bats` — 39 spec-regression tests
- `tests/cta-format/fixtures/{single-task,multi-task,fail-routing}.md` — golden fixtures

**Updated files:**
- 17 commands in `commands/dr-*.md` — every command now ends with a unified `## Next Steps (CTA)` section referencing the canonical spec
- 5 agents in `agents/` — `planner`, `architect`, `developer`, `reviewer`, `compliance` load `cta-format.md` and emit canonical block
- `skills/datarim-system/backlog-and-routing.md` — Mode Transition table now references cta-format and documents Layer-to-command map for FAIL-Routing
- `skills/visual-maps/pipeline-routing.md` — added CTA decision points and FAIL-Routing diagram
- `skills/visual-maps/stage-process-flows.md` — added CTA emission map per stage
- `docs/commands.md` — documented the unified CTA contract
- `docs/skills.md` — added `cta-format` to skill catalog
- `VERSION`, `README.md`, `CLAUDE.md` — bumped to 1.16.0
- `Projects/Datarim/{README.md, CLAUDE.md}` — version bump
- `Projects/Websites/datarim.club/` — changelog, features, 17 command pages, new skill page, 5 agent pages

### Class A/B Gate

This change is **Class A** (touches public framework contract — output format every user sees). Approved: human (Pavel), 2026-04-25, via `/dr-prd TUNE-0032` PRD review.

### Rationale

User feedback: "После создания нескольких задач в бэклоге и при одновременной работе над несколькими проектами и задачами часто не понятно, какое действие нужно выполнять." (TUNE-0032 source).

Research (`datarim/insights/INSIGHTS-TUNE-0032.md`) established:
1. clig.dev + Atlassian Forge CLI principles canonize numbered + primary CTAs
2. Cognitive load research (Miller, Hick's Law, Chernev 2015) sets sweet spot at 3 options, max 5
3. Box-drawing characters (`─`) cause Windows mojibake (Claude Code issue #34247) — switched to safe Markdown `---` HR
4. Codebase audit showed 0/15 commands included task ID in CTA, 0/15 marked primary action

### Testability

39 bats tests guard against drift:
- Skill file existence + frontmatter
- Every command file references `cta-format.md`
- Every named agent loads the skill
- Routing skill points to cta-format
- Anti-pattern regression (no box-drawing in any command)
- Fixtures invariants (HR wrapping, exactly one primary marker)

### Operating Model Note

Runtime ↔ repo for `agents/`, `skills/`, `commands/`, `templates/` is via symlinks (`$HOME/.claude/skills` → `code/datarim/skills`). Edits in runtime land directly in repo — no `scripts/curate-runtime.sh` step needed for these scopes. `tests/` is repo-only (not symlinked).

### Backwards Compatibility

- Old free-form `## Next Steps` sections fully replaced. Archived reflection docs referencing old format remain immutable (no breaking change to history).
- Pipeline routing logic unchanged — only the output format was reformulated.
- Mode Transition automatic transitions preserved (verified via test in `tests/cta-format.bats` and integration check that all transitions are still listed in `backlog-and-routing.md`).

### Affected by Future Changes

Any future change to the CTA format MUST update `skills/cta-format.md`, regenerate fixtures in `tests/cta-format/fixtures/`, and update this evolution log.
