# 2026-Q2 — TUNE-0304: Universal directory-per-skill layout

**Ships in:** Datarim v2.21.0
**Date:** 2026-05-25
**Source task:** TUNE-0304
**Type:** schema migration (Class A — applies to all skills + agents + commands + templates)

## What changed

Three orthogonal contracts were re-aligned with the agentskills.io v1.0.0
open standard adopted by 32 AI tooling vendors:

1. **Layout.** All 55 skills moved from flat `skills/<name>.md` to
   `skills/<name>/SKILL.md`. The 11 pre-existing split-architecture skills
   gained a router `SKILL.md` co-located with their fragment files; the 44
   flat skills were wrapped in their own directory. After Phase 5 contract
   removal there are exactly 55 directories under `skills/` (plus the
   reserved Codex `.system/` namespace and `references/`).

2. **Frontmatter.** The datarim-private `runtime:` field was dropped
   entirely (no runtime reads it). Hard-coded `model: sonnet|opus|haiku`
   bindings were replaced with `model: inherit` as default, with an
   optional `metadata.model_tier: reasoning|balanced|fast|cheap` for audit
   intent. Tier→model mapping centralised in `config/model-tiers.yaml`.

3. **Sibling references.** Inside each SKILL.md, references to co-located
   bundle files are now sibling-relative (`pipeline-routing.md`) rather
   than repo-root-relative (`skills/visual-maps/pipeline-routing.md`).
   Per the agentskills.io contract, SKILL.md + co-located assets form a
   portable bundle — repo-root paths broke whenever an agent's cwd was
   outside the framework repo. This was the operator-flagged defect closed
   during `/dr-qa` round 1.

## Why now

- Datarim positioned itself as runtime-agnostic OSS framework, but the
  flat layout looked idiosyncratic next to Claude / Cursor / Goose
  packages that adopted agentskills.io.
- `model: sonnet` literally fails on Codex CLI (no Sonnet) and on Cursor.
  52 files carried the broken binding.
- Adding a new runtime under the old schema required editing N×{skills,
  agents} files — anti-pattern (single-source mapping per
  `feedback_envvar_validator_distribution_chain.md`).

## Migration matrix

| Source layout | Target layout | Cost |
|---------------|---------------|------|
| `skills/<name>.md` (44 flat) | `skills/<name>/SKILL.md` (new dir) | `migrate-skill.sh` |
| `skills/<name>.md` + `skills/<name>/*.md` (11 split-arch) | `skills/<name>/SKILL.md` + existing siblings | `migrate-skill.sh` (rename + frontmatter normalise) |
| `runtime: [claude, codex]` (52 files) | dropped | sed via `migrate-skill.sh` |
| `model: sonnet/opus/haiku` (33 files) | `model: inherit` + optional `metadata.model_tier:` | per-file judgment for capability-critical skills |
| 38 sibling refs (`skills/<own>/file.md`) inside 6 SKILL.md | sibling-relative (`file.md`) | targeted sed during `/dr-do` round 5 |
| 4 legacy refs in `dev-tools/hooks/dr-output-stop.py` | `skills/<name>/SKILL.md` | targeted sed |

## Deferred (operator decision)

- **Codex 55→1 dir-symlink collapse.** PRD V-AC-7 wants
  `~/.agents/skills/<name>` (industry research D5); plan §6.5 wants
  `~/.codex/skills/datarim` (existing TUNE-0297 wrapper namespace).
  Constraint C5 says existing paths must remain resolvable. L5
  architectural pick — operator must choose. TUNE-0297 wrappers
  remain functional (Codex live smoke 2026-05-25 confirms discovery
  через `~/.codex/skills/`).
- **Cursor IDE live smoke.** Cursor licence not held by operator at ship
  time — R7 accepted-risk recorded in PRD. `install.sh --with-cursor`
  ships as deferred-validation; first Cursor user closes this gap.

## Test surface

48 bats green across 5 suites:

- `tests/check-skill-layout.bats` — 9 cases (strict + hybrid modes)
- `tests/check-skill-frontmatter.bats` — 13 cases (new schema)
- `tests/migrate-skill.bats` — 11 cases (idempotent + dry-run + force)
- `tests/rewrite-skill-refs.bats` — 9 cases (BSD/GNU sed compat)
- `tests/check-skill-sibling-refs.bats` — 6 cases (sibling-ref invariant)

All five new dev-tools/* scripts pass `shellcheck -S warning`.

## Lessons learned

1. **Path format is part of the bundle contract.** Physical co-location
   (Phase 2-3) is necessary but not sufficient — the textual references
   inside SKILL.md must also be portable. The operator caught this at QA
   time after 4 rounds of /dr-do, because no validator enforced it.
   `check-skill-sibling-refs.sh` plugs the hole going forward.

2. **Deferring destructive ops is correct.** Phase 5 contract removal
   (delete 55 flat sources) waited until: (a) Phase 0/1/2/3/4 baseline
   established; (b) hybrid coexistence verified PASS for ≥1 cycle;
   (c) live smoke in both Claude Code and Codex CLI. The five-step
   sequence prevents «migration looks done but discovery is silently
   broken in runtime X».

3. **L1 inline decisions kept the round count low.** Four agent
   clarifications during /dr-do (model-tiers.yaml location, runtime:
   drop semantics, hybrid-mode flag, Phase 5 destructive gate) all
   resolved within the same cycle per the L1 Class A inline rule
   (autonomous-mode skill). Only the Codex path conflict + Phase 5
   destructive op escalated to operator L5.

## Rollback

Per `docs/how-to/migrate-to-skill-md-layout.md` § Rollback — revert each
commit individually:

- Phase 5 deletion: `git revert <SHA>` restores 55 flat sources.
- Phase 4: `git revert <SHA>` removes `--with-cursor`.
- Phase 3: `git revert <cfa3f27>` undoes 44 flat-→-nested migrations and
  the 146-file repo-wide ref rewrite.
- Phase 2: `git revert <c529751>` undoes 11 split-arch migrations.
- Phase 1: `git revert <97c16a7>` removes new dev-tools/* validators.

Each phase is independently reversible.
