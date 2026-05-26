---
title: Migrate a flat skill to the SKILL.md layout
audience: framework-developer
applies-to: Datarim v2.21.0+
---

# Migrate a flat skill to the SKILL.md layout

Background: Datarim v2.21.0 adopts the universal directory-per-skill layout
(`skills/<name>/SKILL.md`) shared by Claude Code, Codex CLI, Cursor, and 32+
other AI tool vendors. This runbook describes the per-skill migration step,
the cross-reference rewrite, and rollback.

## Prerequisites

- Clean working tree on `main` (or task branch).
- `bats` test suite green: `bats tests/check-skill-layout.bats
  tests/check-skill-frontmatter.bats tests/migrate-skill.bats
  tests/rewrite-skill-refs.bats`.
- Baseline counters captured (see `datarim/phase0/`): flat-skill count,
  cross-ref count, paired-dir count. Compare against post-migration to
  confirm zero unintended drift.

## Step 1 — Pilot one skill (dry-run)

```bash
dev-tools/migrate-skill.sh --root . --skill <name> --dry-run
```

Inspect the planned normalised frontmatter. Confirm `runtime:` is dropped
and `model: sonnet|opus|haiku` is rewritten to `model: inherit`. Other keys
are preserved verbatim.

## Step 2 — Migrate the skill

```bash
dev-tools/migrate-skill.sh --root . --skill <name>
```

Effect:

- Creates `skills/<name>/` if absent.
- Writes `skills/<name>/SKILL.md` with normalised frontmatter.
- **Leaves the original `skills/<name>.md` in place.** This is intentional:
  it keeps the file discoverable under the legacy flat layout during the
  hybrid window, and Phase 5 removes the flat originals in a single
  contract step after all cross-refs are rewritten and live runtimes are
  verified.

## Step 3 — Verify the layout

```bash
dev-tools/check-skill-layout.sh --root .
dev-tools/check-skill-frontmatter.sh --root .
```

Both must exit 0. The frontmatter checker emits one `WARN` per skill that
still carries a legacy top-level `runtime:` — these are flat-source files,
not the new SKILL.md targets. Migration progress is measured by the
descending count of these warnings.

## Step 4 — Rewrite cross-references (after all skills migrated)

Defer this step until every skill has its `SKILL.md` in place. Then:

```bash
dev-tools/rewrite-skill-refs.sh --root . --dry-run     # preview
dev-tools/rewrite-skill-refs.sh --root .               # apply
```

Effect: `skills/<name>.md` → `skills/<name>/SKILL.md` across `*.md / *.sh /
*.yaml / *.yml`, excluding `documentation/archive/**` (historical refs are
frozen). The rewrite is idempotent — a second invocation produces zero
diff.

Verification:

```bash
grep -rE 'skills/[a-z][a-z0-9_-]+\.md' \
    --include='*.md' --include='*.sh' --include='*.yaml' --include='*.yml' \
    . | grep -v 'documentation/archive/' | wc -l
```

Expected: `0`.

## Step 5 — Live runtime smoke

Restart Claude Code (and Codex CLI, if used) — running sessions cache
skill discovery and will not see the new layout until restart. Then
invoke at least three migrated skills/commands in each runtime; record
output under `datarim/qa/qa-report-TUNE-0304-live-smoke.md` (V-AC-11).

## Rollback

Per-skill rollback is trivial because the flat originals are preserved:

```bash
rm -rf skills/<name>/SKILL.md
rmdir skills/<name>/ 2>/dev/null || true   # only if dir is empty
```

The pre-migration state is the live state until Phase 5 contracts the
flat originals. If a cross-ref rewrite (`rewrite-skill-refs.sh`) needs to
be undone, revert the git commit — the rewrite is a single mechanical
substitution.

## Why not just `mv`?

The migration COPIES the flat source rather than moving it because:

- The hybrid window must support consumers still resolving
  `skills/<name>.md` (active sessions, cached agent caches, downstream
  installers mid-rollout). A `mv` would break them immediately.
- Phase 5 contract removal is a separate atomic step gated on live-smoke
  verification; coupling the two would force a re-run of the entire
  migration on rollback.

## Frontmatter normalisation contract

- `runtime: …` (top-level) is dropped entirely. The value is universally
  `[claude, codex]` across the existing 51 skills that carry it; preserving
  it under `metadata.runtime` would add cluttered noise without semantic
  gain. (L1 Class A inline decision from `/dr-do` round 2 — see
  `datarim/tasks/TUNE-0304-init-task.md` Q&A round 3.)
- `model: sonnet|opus|haiku` → `model: inherit`. Explicit capability
  overrides remain explicit if the skill needs them — but the migrator
  always normalises hard aliases to `inherit`. If a skill needs to keep
  its hard alias, add `model: opus  # capability-driven` back after
  migration and document the override in `config/model-tiers.yaml`.
- All other keys (`name`, `description`, `current_aal`, `target_aal`,
  `metadata:` block) are preserved verbatim in original order.
