# Changelog

All notable changes to the Datarim framework are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] — 2026-05-09

**Datarim Evolution V2 — multi-runtime framework (Claude + Codex).** TUNE-0114 umbrella ship.

### Added
- Multi-runtime install — `install.sh` now accepts `--with-claude`, `--with-codex`, `--project DIR`, `--yes`, `--dry-run`, `--force` (no flags = print help; legacy `--copy` still implies Claude with WARN).
- `AGENTS.md` — symlink → `CLAUDE.md` so Codex CLI and other agent runtimes that read `AGENTS.md` by convention work out of the box.
- 14 superpowers skills absorbed: 4 verbatim port (`finishing-a-development-branch`, `receiving-code-review`, `systematic-debugging`, `verification-before-completion`), 8 intent-layer rewrites (`brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `requesting-code-review`, `subagent-driven-development`, `using-git-worktrees`, `writing-plans`, `writing-skills`), 2 merges (`test-driven-development` → `testing.md` § Discipline; `using-superpowers` → `datarim-system.md` § Skill Discovery).
- Per-skill `runtime: [claude, codex]` + `current_aal` / `target_aal` frontmatter on all 38 top-level skills (per AAL Mandate; classification per PRD-TUNE-0114 §7).
- `dev-tools/measure-skill-token-cost.sh` — token-budget regression gate (AC-4 idle hot-path ≤+16% + per-existing-file ≤+30%).
- `dev-tools/check-skill-frontmatter.sh` — AC-8 standalone validator for `runtime:` + AAL keys + AGENTS.md symlink.
- `CHANGELOG.md` — Keep-a-Changelog format introduced.
- `.datarim/baseline-v1.23.0.tokens` — frozen baseline for token-budget verification.

### Changed
- **Honest positioning** — Datarim is now described as **multi-runtime framework (Claude + Codex)**, not "vendor-neutral". Cursor / Goose / Aider — future milestones, not current scope.
- `install.sh` — flag-based architecture; collision handling via atomic `mv -T` backup; `--project DIR` copy mode rejects system paths (`/etc`, `/usr`, `/bin`, `/sbin`, `/System`); `~/.${runtime}/.install.lock` lockfile blocks concurrent runs.
- `skills/datarim-system.md` § Skill Discovery — meta-navigation rewrite (merged from `using-superpowers`).
- `skills/testing.md` § Discipline — TDD discipline appended (merged from `test-driven-development`); supporting fragment `skills/testing/tdd-discipline.md`.

### Notes
- **Codex disclaimer:** Codex experience may differ — no `Task` / `TodoWrite` primitives. Intent-layer rewrites use functional prose so the absorbed skills work runtime-agnostically.
- **No breaking changes for existing Claude installs.** Refresh via `./install.sh --with-claude` — symlink layout preserved.
- Sub-tasks unblocked: TUNE-0115 (Adversarial Review skill split), TUNE-0117 (Diátaxis reorg), TUNE-0118 (`/dr-status` pull-mode), TUNE-0119 (Party Mode → Consilium-lite).
- Follow-ups spawned: TUNE-0125 (project-local evolution learning routing), TUNE-0116 (Module Manifest — separate task).

## [1.24.0] — 2026-05-07

### Added
- _(TUNE-0109)_ Secure-by-default Network Exposure Gate (tiered model, reusable CI workflow)

## [1.24.0] — 2026-05-07

### Added
- _(TUNE-0109)_ Secure-by-default Network Exposure Gate (tiered model, reusable CI workflow)

## [1.23.0] — 2026-05-04

Baseline reference for TUNE-0114 token-cost regression measurements.
